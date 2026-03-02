import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool read;
  final DateTime? createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> data;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.read,
    required this.createdAt,
    required this.readAt,
    required this.data,
  });

  factory AppNotification.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();

    DateTime? _toDt(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return AppNotification(
      id: doc.id,
      title: (m["title"] ?? "Notification").toString(),
      body: (m["body"] ?? "").toString(),
      type: (m["type"] ?? "generic").toString(),
      read: (m["read"] as bool?) ?? false,
      createdAt: _toDt(m["createdAt"]),
      readAt: _toDt(m["readAt"]),
      data: (m["data"] is Map) ? Map<String, dynamic>.from(m["data"] as Map) : <String, dynamic>{},
    );
  }
}

class NotificationsRepo {
  final FirebaseFirestore _db;
  NotificationsRepo({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) {
    return _db.collection("users").doc(uid).collection("notifications");
  }

  /// Used by bell badge (dot / count).
  Stream<int> unreadCount(String uid) {
    return _col(uid)
        .where("read", isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  /// Stream the list for the Notification Center.
  Stream<List<AppNotification>> notifications(String uid, {int limit = 100}) {
    return _col(uid)
        .orderBy("createdAt", descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(AppNotification.fromDoc).toList());
  }

  Future<void> markRead({required String uid, required String notifId}) async {
    await _col(uid).doc(notifId).set(
      {
        "read": true,
        "readAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteOne({required String uid, required String notifId}) async {
    await _col(uid).doc(notifId).delete();
  }

  Future<void> markAllRead(String uid) async {
    // Query only unread, then batch update.
    final q = await _col(uid).where("read", isEqualTo: false).get();
    if (q.docs.isEmpty) return;

    const chunkSize = 400;
    for (var i = 0; i < q.docs.length; i += chunkSize) {
      final batch = _db.batch();
      final chunk = q.docs.skip(i).take(chunkSize);

      for (final d in chunk) {
        batch.set(
          d.reference,
          {
            "read": true,
            "readAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<void> clearAll(String uid) async {
    final q = await _col(uid).get();
    if (q.docs.isEmpty) return;

    const chunkSize = 400;
    for (var i = 0; i < q.docs.length; i += chunkSize) {
      final batch = _db.batch();
      final chunk = q.docs.skip(i).take(chunkSize);

      for (final d in chunk) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }
}