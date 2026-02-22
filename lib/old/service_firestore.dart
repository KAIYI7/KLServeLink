import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceUiModel {
  final String id;
  final String title;
  final String category;
  final double priceFrom;
  final double ratingAvg;
  final String providerId;

  const ServiceUiModel({
    required this.id,
    required this.title,
    required this.category,
    required this.priceFrom,
    required this.ratingAvg,
    required this.providerId,
  });
}

class ServiceFirestore {
  final _db = FirebaseFirestore.instance;

  Stream<List<ServiceUiModel>> streamPopular({int limit = 3}) {
    final q = _db
        .collection('services')
        .where('isActive', isEqualTo: true)
        .orderBy('ratingAvg', descending: true)
        .limit(limit);

    return q.snapshots().map((snap) {
      return snap.docs.map((d) {
        final m = d.data();
        return ServiceUiModel(
          id: d.id,
          title: (m['title'] ?? 'Service').toString(),
          category: (m['category'] ?? '').toString(),
          priceFrom: (m['priceFrom'] is num) ? (m['priceFrom'] as num).toDouble() : 0.0,
          ratingAvg: (m['ratingAvg'] is num) ? (m['ratingAvg'] as num).toDouble() : 0.0,
          providerId: (m['providerId'] ?? '').toString(),
        );
      }).toList();
    });
  }
}