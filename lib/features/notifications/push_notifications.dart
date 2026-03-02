import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import '../reviews/screens/all_reviews_screen.dart';
import '../seeker/bookings/screens/booking_detail_screen.dart';
import '../chat/screens/chat_detail_screen.dart';
import '../provider/bookings/screens/provider_booking_details_screen.dart';
import 'screens/notifications_screen.dart';
import '../seeker/navigation/seeker_nav_registry.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Required for background isolate.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Rely on FCM "notification" payload for background/terminated display.
}

class PushNotifications {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static GlobalKey<NavigatorState>? _navKey;
  static bool _inited = false;

  static const String channelId = "kl_default_channel";
  static const String channelName = "KLServeLink";
  static const String channelDesc = "KLServeLink notifications";

  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<String>? _tokenRefreshSub;

  static Future<void> init({required GlobalKey<NavigatorState> navigatorKey}) async {
    if (_inited) return;
    _inited = true;

    _navKey = navigatorKey;

    // Background handler registration (must be set early).
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _initLocalNotifications();
    await _requestAndroid13Permission();

    _listenForegroundMessages();
    _listenNotificationTaps();

    _startTokenSync();
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('ic_stat_klservelink');
    const initSettings = InitializationSettings(android: androidInit);

    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload);
          if (data is Map) {
            _routeFromData(Map<String, dynamic>.from(data));
          }
        } catch (_) {}
      },
    );

    // Create Android channel (must exist for consistent behaviour).
    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.high,
    );

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> _requestAndroid13Permission() async {
    // Android 13+ runtime permission for notifications.
    // (This call is safe on lower Android versions — it just returns null/false.)
    try {
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static void _listenForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) async {
      final n = msg.notification;
      final title = (n?.title ?? msg.data["title"] ?? "KLServeLink").toString();
      final body = (n?.body ?? msg.data["body"] ?? "").toString();

      if (body.trim().isEmpty && title.trim().isEmpty) return;

      // Use a stable-ish id.
      final id = max(1, DateTime.now().millisecondsSinceEpoch ~/ 1000);

      final details = const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_klservelink',
        ),
      );

      // Store the data payload so taps can deep-link.
      await _local.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: jsonEncode(msg.data),
      );

    });
  }

  static void _listenNotificationTaps() {
    // App opened from background via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _routeFromData(msg.data);
    });

    // App opened from terminated via notification tap
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg == null) return;
      // Wait until first frame so navigator exists.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _routeFromData(msg.data);
      });
    });
  }

  static void _startTokenSync() {
    // One auth listener; write token whenever user logs in.
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.userChanges().listen((user) async {
      if (user == null) return;
      await _upsertToken(uid: user.uid);
    });

    // Token refresh listener (single subscription).
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await _saveToken(uid: uid, token: token);
    });
  }

  static Future<void> _upsertToken({required String uid}) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _saveToken(uid: uid, token: token);
    } catch (_) {}
  }

  static Future<void> _saveToken({required String uid, required String token}) async {
    await FirebaseFirestore.instance.collection("users").doc(uid).set(
      {
        "fcmToken": token,
        "fcmUpdatedAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static void _routeFromData(Map<String, dynamic> data) {
    final nav = _navKey?.currentState;
    if (nav == null) return;

    String s(dynamic v) => (v ?? "").toString();

    final type = s(data["type"]).toLowerCase();

    final peerUid = s(data["peerUid"]).isNotEmpty
        ? s(data["peerUid"])
        : (s(data["fromUid"]).isNotEmpty ? s(data["fromUid"]) : s(data["senderId"]));

    final bookingId = s(data["bookingId"]).isNotEmpty ? s(data["bookingId"]) : s(data["id"]);
    final serviceId = s(data["serviceId"]);

    // Chat
    if (peerUid.isNotEmpty) {
      nav.push(MaterialPageRoute(builder: (_) => ChatDetailScreen(peerUid: peerUid)));
      return;
    }

    // Booking
    if (bookingId.isNotEmpty) {
      final looksProvider =
          type.contains("booking_created") || type.contains("booking_cancelled") || type.contains("provider");

      if (looksProvider) {
        nav.push(MaterialPageRoute(builder: (_) => ProviderBookingDetailsScreen(bookingId: bookingId)));
        return;
      }

      // Seeker booking details needs SeekerNavController
      final seekerNav = SeekerNavRegistry.I.current;
      if (seekerNav != null) {
        nav.push(MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: bookingId, nav: seekerNav)));
      } else {
        // Fallback: open notification center (user can tap inside list later)
        nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen(isProvider: false)));
      }
      return;
    }

    // Reviews
    if (serviceId.isNotEmpty) {
      nav.push(MaterialPageRoute(builder: (_) => AllReviewsScreen(serviceId: serviceId)));
      return;
    }

    // Fallback: Notification center
    final seekerNav = SeekerNavRegistry.I.current;
    final isProvider = type.contains("review") || type.contains("booking_created") || type.contains("booking_cancelled");
    nav.push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(isProvider: isProvider, seekerNav: seekerNav),
      ),
    );
  }
}