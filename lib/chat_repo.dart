import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRepo {
  final FirebaseFirestore db;
  ChatRepo({FirebaseFirestore? db}) : db = db ?? FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchThreads(String myUid) {
    return db
        .collection('threads')
        .where('participants', arrayContains: myUid)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUser(String uid) {
    return db.collection('users').doc(uid).snapshots();
  }

  Future<Map<String, dynamic>?> getUser(String uid) async {
    final d = await db.collection('users').doc(uid).get();
    return d.data();
  }
}