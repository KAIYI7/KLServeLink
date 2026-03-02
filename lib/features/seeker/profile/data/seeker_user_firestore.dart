import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecommendationReason {
  final String becauseServiceId;
  final String becauseText;
  final String source;
  final double contribution;
  final double similarity;
  final double userWeight;

  RecommendationReason({
    required this.becauseServiceId,
    required this.becauseText,
    required this.source,
    required this.contribution,
    required this.similarity,
    required this.userWeight,
  });

  factory RecommendationReason.fromMap(Map<String, dynamic> m) {
    return RecommendationReason(
      becauseServiceId: (m['becauseServiceId'] ?? '').toString(),
      becauseText: (m['becauseText'] ?? '').toString(),
      source: (m['source'] ?? '').toString(),
      contribution: (m['contribution'] as num?)?.toDouble() ?? 0.0,
      similarity: (m['similarity'] as num?)?.toDouble() ?? 0.0,
      userWeight: (m['userWeight'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class RecommendationsPayload {
  final List<String> serviceIds;
  final Map<String, List<RecommendationReason>> reasons;
  final Map<String, dynamic> meta;
  final String algo;

  RecommendationsPayload({
    required this.serviceIds,
    required this.reasons,
    required this.meta,
    required this.algo,
  });
}

class SeekerUserFirestore {
  final _db = FirebaseFirestore.instance;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError("Not authenticated");
    return uid;
  }

  Stream<RecommendationsPayload?> streamMyRecommendationsPayload({int limit = 5}) {
    final uid = _uid;

    return _db.collection("users").doc(uid).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;

      final rec = (data["recommendations"] as Map<String, dynamic>?) ?? {};

      final idsAll = ((rec["serviceIds"] as List?) ?? const [])
          .map((e) => e.toString())
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final ids =
      (idsAll.length > limit) ? idsAll.sublist(0, limit) : idsAll;

      final rawReasons = rec["reasons"] as Map<String, dynamic>?;
      final reasons = <String, List<RecommendationReason>>{};

      if (rawReasons != null) {
        for (final sid in ids) {
          final arr = rawReasons[sid];
          if (arr is List) {
            final parsed = <RecommendationReason>[];
            for (final x in arr) {
              if (x is Map<String, dynamic>) {
                parsed.add(RecommendationReason.fromMap(x));
              } else if (x is Map) {
                parsed.add(
                  RecommendationReason.fromMap(
                    Map<String, dynamic>.from(x),
                  ),
                );
              }
            }
            if (parsed.isNotEmpty) {
              reasons[sid] = parsed;
            }
          }
        }
      }

      return RecommendationsPayload(
        serviceIds: ids,
        reasons: reasons,
        meta: (rec["meta"] as Map<String, dynamic>?) ?? {},
        algo: (rec["algo"] ?? "").toString(),
      );
    });
  }

  Stream<String> streamMyName() {
    final uid = _uid;
    return _db.collection('users').doc(uid).snapshots().map((d) {
      final m = d.data();
      final name = (m?['name'] ?? '').toString().trim();
      if (name.isEmpty) return "User";
      return name;
    });
  }

  Stream<List<String>> streamMyRecommendations({int limit = 5}) {
    final uid = _uid;
    return _db.collection('users').doc(uid).snapshots().map((d) {
      final m = d.data() ?? {};
      final rec = (m['recommendations'] as Map?)?.cast<String, dynamic>();
      final ids = (rec?['serviceIds'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
          const <String>[];
      return ids.take(limit).toList();
    });
  }

}