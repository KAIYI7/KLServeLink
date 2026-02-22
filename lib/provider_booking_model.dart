import 'package:cloud_firestore/cloud_firestore.dart';

enum ProviderBookingStatus { all, pending, accepted, declined, completed, cancelled }

ProviderBookingStatus bookingStatusFromString(String s) {
  switch (s) {
    case 'accepted':
      return ProviderBookingStatus.accepted;
    case 'completed':
      return ProviderBookingStatus.completed;
    case 'declined':
      return ProviderBookingStatus.declined;
    case 'cancelled':
      return ProviderBookingStatus.cancelled;
    case 'pending':
      return ProviderBookingStatus.pending;
    default:
      return ProviderBookingStatus.pending;
  }
}

String bookingStatusToString(ProviderBookingStatus s) {
  switch (s) {
    case ProviderBookingStatus.accepted:
      return 'accepted';
    case ProviderBookingStatus.completed:
      return 'completed';
    case ProviderBookingStatus.declined:
      return 'declined';
    case ProviderBookingStatus.cancelled:
      return 'cancelled';
    case ProviderBookingStatus.pending:
      return 'pending';
    case ProviderBookingStatus.all:
      return 'all';
  }
}

class ProviderBooking {
  final String id;
  final String providerId;

  final String seekerId;
  final String seekerName;
  final String? seekerEmail;

  final String serviceId;
  final String serviceName;
  final String? servicePhotoUrl;

  final DateTime scheduledAt;
  final String locationText;
  final double totalAmount;

  final double? locationLat;
  final double? locationLng;

  final double? providerLat;
  final double? providerLng;
  final double? distanceKm;

  final ProviderBookingStatus status;

  ProviderBooking({
    required this.id,
    required this.providerId,
    required this.seekerId,
    required this.seekerName,
    required this.seekerEmail,
    required this.serviceId,
    required this.serviceName,
    required this.servicePhotoUrl,
    required this.scheduledAt,
    required this.locationText,
    required this.totalAmount,
    required this.locationLat,
    required this.locationLng,
    required this.providerLat,
    required this.providerLng,
    required this.distanceKm,
    required this.status,
  });

  factory ProviderBooking.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ProviderBooking(
      id: doc.id,
      providerId: (d['providerId'] ?? '') as String,
      seekerId: (d['seekerId'] ?? '') as String,
      seekerName: (d['seekerName'] ?? 'Seeker') as String,
      seekerEmail: d['seekerEmail'] as String?,
      serviceId: (d['serviceId'] ?? '') as String,
      serviceName: (d['serviceName'] ?? 'Service') as String,
      servicePhotoUrl: d['servicePhotoUrl'] as String?,
      scheduledAt: (d['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      locationText: (d['locationText'] ?? 'Kuala Lumpur') as String,
      totalAmount: ((d['totalAmount'] ?? 0) as num).toDouble(),
      locationLat: (d['locationLat'] is num) ? (d['locationLat'] as num).toDouble() : null,
      locationLng: (d['locationLng'] is num) ? (d['locationLng'] as num).toDouble() : null,
      providerLat: (d['providerLat'] is num) ? (d['providerLat'] as num).toDouble() : null,
      providerLng: (d['providerLng'] is num) ? (d['providerLng'] as num).toDouble() : null,
      distanceKm: (d['distanceKm'] is num) ? (d['distanceKm'] as num).toDouble() : null,
      status: bookingStatusFromString((d['status'] ?? 'pending') as String),
    );
  }
}