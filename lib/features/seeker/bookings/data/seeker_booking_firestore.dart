import 'package:cloud_firestore/cloud_firestore.dart';

enum SeekerBookingTab { upcoming, completed, cancelled }

class SeekerBookingFirestore {
  final _db = FirebaseFirestore.instance;

  Stream<List<BookingUi>> streamMyBookings({
    required String seekerId,
    required SeekerBookingTab tab,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('bookings')
        .where('seekerId', isEqualTo: seekerId);

    // Firestore-side filter:
    // upcoming: pending/accepted
    // completed: completed
    if (tab == SeekerBookingTab.completed) {
      q = q.where('status', isEqualTo: 'completed');
    } else if (tab == SeekerBookingTab.cancelled) {
      q = q.where('status', whereIn: ['cancelled', 'declined']);
    } else {
      q = q.where('status', whereIn: ['pending', 'accepted', 'confirmed']);
    }

    q = q.orderBy('scheduledAt', descending: false);

    return q.snapshots().map((snap) {
      return snap.docs.map((d) => BookingUi.fromDoc(d)).toList();
    });
  }
}

enum BookingStatus { upcoming, completed, cancelled }

class BookingUi {
  final String id;
  final String serviceId;
  final String providerId;
  final String title;
  final String locationText;
  final String locationArea;
  final double? locationLat;
  final double? locationLng;
  final double? providerLat;
  final double? providerLng;
  final double serviceRating;
  final double unitPrice;
  final double totalAmount;
  final String paymentMethod;
  final DateTime scheduledAt;
  final BookingStatus status;
  final bool isReviewed;
  final int? reviewStars;
  final String? reviewText;
  final DateTime? reviewedAt;

  const BookingUi({
    required this.id,
    required this.serviceId,
    required this.providerId,
    required this.title,
    required this.locationText,
    required this.locationArea,
    required this.locationLat,
    required this.locationLng,
    required this.providerLat,
    required this.providerLng,
    required this.serviceRating,
    required this.unitPrice,
    required this.totalAmount,
    required this.paymentMethod,
    required this.scheduledAt,
    required this.status,
    this.isReviewed = false,
    this.reviewStars,
    this.reviewText,
    this.reviewedAt,
  });

  static BookingUi fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};

    final statusStr = (m['status'] ?? 'pending').toString().toLowerCase();
    final bookingStatus = switch (statusStr) {
      'completed' => BookingStatus.completed,
      'cancelled' => BookingStatus.cancelled,
      'declined'  => BookingStatus.cancelled,
      _ => BookingStatus.upcoming,
    };

    final ts = m['scheduledAt'];
    final dt = (ts is Timestamp) ? ts.toDate() : DateTime.now();

    final lat = (m['locationLat'] is num) ? (m['locationLat'] as num).toDouble() : null;
    final lng = (m['locationLng'] is num) ? (m['locationLng'] as num).toDouble() : null;

    final pLat = (m['providerLat'] is num) ? (m['providerLat'] as num).toDouble() : null;
    final pLng = (m['providerLng'] is num) ? (m['providerLng'] as num).toDouble() : null;

    final sr = (m['serviceRating'] is num)
        ? (m['serviceRating'] as num).toDouble()
        : ((m['rating'] is num) ? (m['rating'] as num).toDouble() : 0.0);

    final rs = (m['reviewStars'] is num) ? (m['reviewStars'] as num).toInt() : null;
    final rtRaw = (m['reviewText'] ?? '').toString().trim();
    final reviewedAtTs = m['reviewedAt'];
    final reviewedAt = (reviewedAtTs is Timestamp) ? reviewedAtTs.toDate() : null;

    return BookingUi(
      id: doc.id,
      serviceId: (m['serviceId'] ?? '').toString(),
      providerId: (m['providerId'] ?? '').toString(),
      title: (m['serviceName'] ?? m['title'] ?? 'Service').toString(),
      locationText: (m['locationText'] ?? m['locationArea'] ?? '').toString(),
      locationArea: (m['locationArea'] ?? m['locationText'] ?? '').toString(),
      locationLat: lat,
      locationLng: lng,
      providerLat: pLat,
      providerLng: pLng,
      serviceRating: sr,
      unitPrice: (m['unitPrice'] is num) ? (m['unitPrice'] as num).toDouble() : 0.0,
      totalAmount: (m['totalAmount'] is num) ? (m['totalAmount'] as num).toDouble() : 0.0,
      paymentMethod: (m['paymentMethod'] ?? 'cash').toString(),
      scheduledAt: dt,
      status: bookingStatus,
      isReviewed: (m['isReviewed'] ?? false) == true,
      reviewStars: rs,
      reviewText: rtRaw.isEmpty ? null : rtRaw,
      reviewedAt: reviewedAt,
    );
  }
}