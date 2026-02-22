import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceResultUi {
  final String id;
  final String title;
  final String category;
  final int priceFrom;
  final double ratingAvg;
  final int ratingCount;

  final double lat;
  final double lng;
  //final String geohash;

  const ServiceResultUi({
    required this.id,
    required this.title,
    required this.category,
    required this.priceFrom,
    required this.ratingAvg,
    required this.ratingCount,
    required this.lat,
    required this.lng,
    // this.geohash,
  });

  factory ServiceResultUi.fromMap(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data();

    return ServiceResultUi(
      id: d.id,
      title: (x["title"] ?? "") as String,
      category: (x["category"] ?? "") as String,
      priceFrom: (x["priceFrom"] as num? ?? 0).toInt(),
      ratingAvg: (x["ratingAvg"] as num? ?? 0).toDouble(),
      ratingCount: (x["ratingCount"] as num? ?? 0).toInt(),
      lat: (x["lat"] as num? ?? 0).toDouble(),
      lng: (x["lng"] as num? ?? 0).toDouble(),

    );
  }
}