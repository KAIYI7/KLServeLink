import 'features/auth/screens/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/core/theme/theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/notifications/push_notifications.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await PushNotifications.init(navigatorKey: rootNavKey);

  runApp(MyApp(navigatorKey: rootNavKey));
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const MyApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildKLTheme(),
      home : const AuthGate(),
    );
  }
}
