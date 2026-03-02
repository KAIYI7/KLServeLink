import 'package:cloud_firestore/cloud_firestore.dart';

class SeekerServiceUi {
  final String id;
  final String providerId;
  final String name;
  final String category;
  final String address;
  final String type;
  final String status;
  final bool autoLockTimeSlots;
  final List<String> photoUrls;
  final String? thumbnailUrl;
  final double price;
  final double discount;
  final double hourlyRate;
  final List<Map<String, dynamic>> pricingRules;
  final Map<String, dynamic>? pricingCaps;
  final int durationHours;
  final int durationMins;
  final String description;
  final bool featured;
  final double ratingAvg;
  final int ratingCount;
  final double? lat;
  final double? lng;
  final String? geohash;

  final double? sentimentScore;
  final List<String> topKeywords;
  final int? reviewsAnalyzed;

  const SeekerServiceUi({
    required this.id,
    required this.providerId,
    required this.name,
    required this.category,
    required this.address,
    required this.type,
    required this.status,
    this.autoLockTimeSlots = true,
    this.photoUrls = const [],
    this.thumbnailUrl,
    required this.price,
    required this.discount,
    required this.hourlyRate,
    required this.pricingRules,
    required this.pricingCaps,
    required this.durationHours,
    required this.durationMins,
    required this.description,
    required this.featured,
    required this.ratingAvg,
    required this.ratingCount,
    this.lat,
    this.lng,
    this.geohash,
    this.sentimentScore,
    this.topKeywords = const [],
    this.reviewsAnalyzed,
  });

  double get rating => ratingAvg;

  factory SeekerServiceUi.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};

    double readDouble(dynamic v, [double fallback = 0]) =>
        (v is num) ? v.toDouble() : fallback;

    int readInt(dynamic v, [int fallback = 0]) =>
        (v is num) ? v.toInt() : fallback;

    final photoUrls = (d["photoUrls"] as List?)
        ?.map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList() ??
        const <String>[];

    final thumbRaw = (d["thumbnailUrl"] ?? "").toString().trim();
    final thumbnailUrl = thumbRaw.isEmpty ? null : thumbRaw;

    final rulesRaw = (d["pricingRules"] as List?)?.cast<dynamic>() ?? const [];
    final rules = rulesRaw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    final ratingAvg = readDouble(d["ratingAvg"], readDouble(d["rating"], 0));
    final ratingCount = readInt(d["ratingCount"], 0);

    final ra = (d['reviewsAnalyzed'] is num)
        ? (d['reviewsAnalyzed'] as num).toInt()
        : null;

    return SeekerServiceUi(
      id: doc.id,
      providerId: (d["providerId"] ?? "") as String,
      name: (d["name"] ?? "") as String,
      category: (d["category"] ?? "") as String,
      address: (d["address"] ?? "") as String,
      type: (d["type"] ?? "onsite") as String,
      status: (d["status"] ?? "active") as String,
      autoLockTimeSlots: (d['autoLockTimeSlots'] ?? true) == true,
      photoUrls: photoUrls,
      thumbnailUrl: thumbnailUrl,
      price: (d["price"] is num) ? (d["price"] as num).toDouble() : 0,
      discount: (d["discount"] is num) ? (d["discount"] as num).toDouble() : 0,
      hourlyRate: readDouble(d["hourlyRate"], 22),
      pricingRules: rules,
      pricingCaps: (d["pricingCaps"] as Map?)?.cast<String, dynamic>(),
      durationHours:
      (d["durationHours"] is num) ? (d["durationHours"] as num).toInt() : 0,
      durationMins:
      (d["durationMins"] is num) ? (d["durationMins"] as num).toInt() : 0,
      description: (d["description"] ?? "") as String,
      featured: (d["featured"] ?? false) as bool,
      ratingAvg: ratingAvg,
      ratingCount: ratingCount,
      lat: (d["lat"] is num) ? (d["lat"] as num).toDouble() : null,
      lng: (d["lng"] is num) ? (d["lng"] as num).toDouble() : null,
      geohash: (d["geohash"] ?? "") == ""
          ? null
          : (d["geohash"] ?? "").toString(),

      sentimentScore: (d["sentiment_score"] is num)
          ? (d["sentiment_score"] as num).toDouble()
          : null,
      topKeywords: (d["top_keywords"] as List?)
          ?.map((e) => e.toString())
          .toList() ??
          const [],
      reviewsAnalyzed: ra,
    );
  }
}

class SeekerServicesRepo {
  final _db = FirebaseFirestore.instance;

  Stream<List<SeekerServiceUi>> streamPopular({int limit = 3}) {
    final q = _db
        .collection("services")
        .where("status", isEqualTo: "active")
        .orderBy("ratingAvg", descending: true)
        .limit(limit);

    return q.snapshots().map(
          (snap) => snap.docs.map((d) => SeekerServiceUi.fromDoc(d)).toList(),
    );
  }

  Stream<List<SeekerServiceUi>> streamFeatured({int limit = 6}) {
    final q = _db
        .collection("services")
        .where("status", isEqualTo: "active")
        .where("featured", isEqualTo: true)
        .orderBy("updatedAt", descending: true)
        .limit(limit);

    return q.snapshots().map(
          (snap) => snap.docs.map((d) => SeekerServiceUi.fromDoc(d)).toList(),
    );
  }

  Stream<List<SeekerServiceUi>> streamByIds(List<String> ids) {
    final clean = ids.where((e) => e.trim().isNotEmpty).toList();
    if (clean.isEmpty) return Stream.value(const <SeekerServiceUi>[]);

    final capped = clean.take(10).toList();

    final q = _db
        .collection("services")
        .where(FieldPath.documentId, whereIn: capped);

    return q.snapshots().map((snap) {
      final byId = <String, SeekerServiceUi>{
        for (final d in snap.docs) d.id: SeekerServiceUi.fromDoc(d),
      };

      // Preserve ranking from AI output
      return capped.where(byId.containsKey).map((id) => byId[id]!).toList();
    });
  }

  Stream<SeekerServiceUi?> streamById(String id) {
    return _db.collection("services").doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return SeekerServiceUi.fromDoc(doc);
    });
  }

  Stream<List<SeekerServiceUi>> watchActive({String? category}) {
    Query<Map<String, dynamic>> q =
    _db.collection("services").where("status", isEqualTo: "active");

    if (category != null && category.trim().isNotEmpty) {
      q = q.where("category", isEqualTo: category);
    }

    q = q.orderBy("updatedAt", descending: true);

    return q.snapshots().map(
          (snap) => snap.docs.map((d) => SeekerServiceUi.fromDoc(d)).toList(),
    );
  }

  Future<List<SeekerServiceUi>> fetchByIds(List<String> ids) async {
    final clean = ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (clean.isEmpty) return [];

    // Split into chunks of max 10
    final chunks = <List<String>>[];
    for (int i = 0; i < clean.length; i += 10) {
      chunks.add(
        clean.sublist(
          i,
          (i + 10 > clean.length) ? clean.length : i + 10,
        ),
      );
    }

    final out = <SeekerServiceUi>[];

    // Fetch chunks (parallel)
    final futures = chunks.map((c) {
      return _db
          .collection("services")
          .where(FieldPath.documentId, whereIn: c)
          .get();
    });

    final snaps = await Future.wait(futures);

    for (final snap in snaps) {
      out.addAll(snap.docs.map((d) => SeekerServiceUi.fromDoc(d)));
    }

    // Restore AI ranking order
    final byId = {for (final s in out) s.id: s};

    return [
      for (final id in clean)
        if (byId[id] != null) byId[id]!,
    ];
  }

}
