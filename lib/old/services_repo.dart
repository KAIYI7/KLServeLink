import 'package:cloud_firestore/cloud_firestore.dart';
import 'service_result_ui.dart';

class ServicesRepo {
  final FirebaseFirestore _db;
  ServicesRepo({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<ServiceResultUi>> watchServices({
    String? query,
    String? categoryKey,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> ref = _db
        .collection("services")
        .where("isActive", isEqualTo: true);

    if (categoryKey != null && categoryKey.isNotEmpty) {
      ref = ref.where("category", isEqualTo: categoryKey);
    }

    final q = (query ?? "").trim().toLowerCase();

    if (q.isNotEmpty) {
      // Prefix search on titleLower
      ref = ref
          .orderBy("titleLower")
          .startAt([q])
          .endAt(["$q\uf8ff"]);
    } else {
      // default ordering when no text query
      ref = ref.orderBy("createdAt", descending: true);
    }

    ref = ref.limit(limit);

    return ref.snapshots().map((QuerySnapshot<Map<String, dynamic>> snap) {
      return snap.docs
          .map<ServiceResultUi>((doc) => ServiceResultUi.fromMap(doc))
          .toList();
    });
  }
}