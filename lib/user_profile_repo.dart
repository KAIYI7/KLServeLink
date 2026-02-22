import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfileRepo {
  final _db = FirebaseFirestore.instance;

  String get uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw StateError("Not authenticated");
    return u.uid;
  }

  DocumentReference<Map<String, dynamic>> get _doc => _db.collection('users').doc(uid);

  Stream<Map<String, dynamic>> watchMe() {
    return _doc.snapshots().map((d) => d.data() ?? {});
  }

  Future<Map<String, dynamic>> getMe() async {
    final d = await _doc.get();
    return d.data() ?? {};
  }

  Future<void> updateMe(Map<String, dynamic> data) async {
    await _doc.set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}