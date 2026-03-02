import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/geohash.dart';

Future<void> seedServices() async {
  final db = FirebaseFirestore.instance;

  // 1) Delete existing docs in services
  // final existing = await db.collection("services").get();
  // for (final d in existing.docs) {
  //   await d.reference.delete();
  // }

  // 2) New seed data
  final data = <Map<String, dynamic>>[
    // Cleaning
    {
      "title": "House Cleaning",
      "category": "cleaning",
      "priceFrom": 23,
      "ratingAvg": 4.9,
      "ratingCount": 1240,
      "providerId": "provider_001",
      "isActive": true,
      "lat": 3.1390,
      "lng": 101.6869, // KLCC-ish
    },
    {
      "title": "Deep Cleaning (Move-in/out)",
      "category": "cleaning",
      "priceFrom": 80,
      "ratingAvg": 4.8,
      "ratingCount": 410,
      "providerId": "provider_004",
      "isActive": true,
      "lat": 3.1319,
      "lng": 101.6841, // Bukit Nanas-ish
    },

    // Plumbing
    {
      "title": "Plumbing Repair",
      "category": "plumbing",
      "priceFrom": 45,
      "ratingAvg": 4.7,
      "ratingCount": 221,
      "providerId": "provider_003",
      "isActive": true,
      "lat": 3.1210,
      "lng": 101.6730, // Brickfields-ish
    },
    {
      "title": "Pipe Leakage Fix",
      "category": "plumbing",
      "priceFrom": 55,
      "ratingAvg": 4.6,
      "ratingCount": 152,
      "providerId": "provider_008",
      "isActive": true,
      "lat": 3.1495,
      "lng": 101.7101, // Ampang-ish
    },

    // Aircon
    {
      "title": "Aircon Service",
      "category": "aircon",
      "priceFrom": 60,
      "ratingAvg": 4.8,
      "ratingCount": 322,
      "providerId": "provider_002",
      "isActive": true,
      "lat": 3.1522,
      "lng": 101.7030,
    },
    {
      "title": "Aircon Chemical Wash",
      "category": "aircon",
      "priceFrom": 120,
      "ratingAvg": 4.9,
      "ratingCount": 198,
      "providerId": "provider_009",
      "isActive": true,
      "lat": 3.1672,
      "lng": 101.7077, // Wangsa Maju-ish
    },

    // Handyman
    {
      "title": "Handyman – Minor Home Repair",
      "category": "handyman",
      "priceFrom": 40,
      "ratingAvg": 4.7,
      "ratingCount": 305,
      "providerId": "provider_005",
      "isActive": true,
      "lat": 3.1348,
      "lng": 101.6296, // Setapak-ish
    },
    {
      "title": "Furniture Assembly",
      "category": "handyman",
      "priceFrom": 50,
      "ratingAvg": 4.8,
      "ratingCount": 170,
      "providerId": "provider_010",
      "isActive": true,
      "lat": 3.1069,
      "lng": 101.6130, // Old Klang Road-ish
    },

    // Tutoring
    {
      "title": "SPM Mathematics Tutor",
      "category": "tutoring",
      "priceFrom": 35,
      "ratingAvg": 4.9,
      "ratingCount": 88,
      "providerId": "provider_006",
      "isActive": true,
      "lat": 3.1560,
      "lng": 101.6621, // Chow Kit-ish
    },
    {
      "title": "English Speaking Coach",
      "category": "tutoring",
      "priceFrom": 40,
      "ratingAvg": 4.8,
      "ratingCount": 64,
      "providerId": "provider_007",
      "isActive": true,
      "lat": 3.1450,
      "lng": 101.6285, // Danau Kota-ish
    },
  ];

  // 3) Insert docs
  for (final s in data) {
    final lat = (s["lat"] as num).toDouble();
    final lng = (s["lng"] as num).toDouble();

    final doc = <String, dynamic>{
      ...s,
      "geohash": GeoHash.encode(lat, lng, precision: 9),

      // optional: helps quick client-side search
      "titleLower": (s["title"] as String).toLowerCase(),

      "createdAt": FieldValue.serverTimestamp(),
    };

    await db.collection("services").add(doc);
  }
}