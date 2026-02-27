import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'provider_booking_model.dart';

class BookingFirestore {
  final _db = FirebaseFirestore.instance;

  Stream<List<ProviderBooking>> streamProviderBookings({
    required String providerId,
    required ProviderBookingStatus filter,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('bookings')
        .where('providerId', isEqualTo: providerId);

    if (filter != ProviderBookingStatus.all) {
      q = q.where('status', isEqualTo: bookingStatusToString(filter));
    }

    // sorting: scheduledAt
    q = q.orderBy('scheduledAt', descending: false);

    return q.snapshots().map((snap) {
      return snap.docs.map(ProviderBooking.fromDoc).toList();
    });
  }

  Future<void> updateStatus({
    required String bookingId,
    required ProviderBookingStatus newStatus,
    required String actorUid,
  }) async {
    final ref = _db.collection('bookings').doc(bookingId);

    await _db.runTransaction((tx) async {
      final updates = {
        'status': bookingStatusToString(newStatus),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == ProviderBookingStatus.accepted) {
        updates['acceptedAt'] = FieldValue.serverTimestamp();
      }

      tx.update(ref, updates);

      // history event
      final h = ref.collection('history').doc();
      tx.set(h, {
        'at': FieldValue.serverTimestamp(),
        'title': _historyTitle(newStatus),
        'subtitle': 'Status updated',
        'actorUid': actorUid,
      });
    });
  }

  String _historyTitle(ProviderBookingStatus s) {
    switch (s) {
      case ProviderBookingStatus.accepted:
        return 'Accept Booking';
      case ProviderBookingStatus.confirmed:
        return 'Confirmed';
      case ProviderBookingStatus.completed:
        return 'Completed';
      case ProviderBookingStatus.declined:
        return 'Declined';
      case ProviderBookingStatus.cancelled:
        return 'Cancelled';
      case ProviderBookingStatus.pending:
        return 'New Booking';
      case ProviderBookingStatus.all:
      default:
        return 'Status updated';
    }
  }

  Future<String> createSeekerBooking({
    required String providerId,
    required String serviceId,
    required String serviceName,
    required DateTime scheduledAt,
    required String locationText,
    required String locationArea,
    required double? locationLat,
    required double? locationLng,
    required String? locationGeohash,
    required String addressId,
    required double totalAmount,
    required double floorPrice,
    required double hourlyRate,
    required int hours,
    required double? rulesDelta,
    required List<Map<String, dynamic>> pricingLines,
    required List<Map<String, dynamic>> pricingRulesSnapshot,
    required double ratingAvg,
    required double? providerLat,
    required double? providerLng,
    required double? distanceKm,
    required String paymentMethodId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError("Not authenticated");

    final seekerName =
        FirebaseAuth.instance.currentUser?.displayName ?? "Seeker";

    final ref = _db.collection("bookings").doc();

    await ref.set({
      "providerId": providerId,
      "seekerId": uid,
      "seekerName": seekerName,
      "serviceId": serviceId,
      "serviceName": serviceName,
      "scheduledAt": Timestamp.fromDate(scheduledAt),
      "status": "pending",
      "totalAmount": totalAmount,
      "addressId": addressId,
      "locationText": locationText,
      "locationArea": locationArea,
      "locationLat": locationLat,
      "locationLng": locationLng,
      "locationGeohash": locationGeohash,
      "floorPrice": floorPrice,
      "hourlyRate": hourlyRate,
      "hours": hours,
      "rulesDelta": rulesDelta,
      "pricingLines": pricingLines,
      "pricingRulesSnapshot": pricingRulesSnapshot,
      "pricingVersion": 1,
      "serviceRating": ratingAvg,
      "isReviewed": false,
      "providerLat": providerLat,
      "providerLng": providerLng,
      "distanceKm": distanceKm,
      "paymentMethod": paymentMethodId,
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    });

    // history subcollection initial event
    await ref.collection("history").add({
      "at": FieldValue.serverTimestamp(),
      "title": "New Booking",
      "subtitle": "Created by seeker",
      "actorUid": uid,
    });

    return ref.id;
  }
}