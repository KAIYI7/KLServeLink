import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedServicesRepo {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _savedCol(String uid) {
    return _db.collection('users').doc(uid).collection('savedServices');
  }

  DocumentReference<Map<String, dynamic>> _savedDoc(String uid, String serviceId) {
    return _savedCol(uid).doc(serviceId);
  }

  Stream<bool> streamIsSaved(String serviceId) {
    final uid = _uid;
    if (uid == null) return Stream.value(false);

    return _savedDoc(uid, serviceId).snapshots().map((doc) => doc.exists);
  }

  Stream<Set<String>> streamMySavedIds() {
    final uid = _uid;
    if (uid == null) return Stream.value(<String>{});

    return _savedCol(uid).snapshots().map(
          (snap) => snap.docs.map((d) => d.id).toSet(),
    );
  }

  Future<bool> isSaved(String serviceId) async {
    final uid = _uid;
    if (uid == null) return false;

    final snap = await _savedDoc(uid, serviceId).get();
    return snap.exists;
  }

  Future<bool> toggle(String serviceId) async {
    final uid = _uid;
    if (uid == null) {
      throw FirebaseAuthException(
        code: 'not-authenticated',
        message: 'Login required',
      );
    }

    final ref = _savedDoc(uid, serviceId);

    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);

      if (snap.exists) {
        tx.delete(ref);
        return false; // unsaved
      }

      tx.set(ref, {
        'serviceId': serviceId,
        'savedAt': FieldValue.serverTimestamp(),
      });

      return true; // saved
    });
  }

  Future<void> save(String serviceId) async {
    final uid = _uid;
    if (uid == null) {
      throw FirebaseAuthException(
        code: 'not-authenticated',
        message: 'Login required',
      );
    }

    await _savedDoc(uid, serviceId).set({
      'serviceId': serviceId,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unsave(String serviceId) async {
    final uid = _uid;
    if (uid == null) {
      throw FirebaseAuthException(
        code: 'not-authenticated',
        message: 'Login required',
      );
    }

    await _savedDoc(uid, serviceId).delete();
  }

  Stream<List<SavedServiceEntry>> streamMySavedEntries({int limit = 100}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const <SavedServiceEntry>[]);

    return _savedCol(uid)
        .orderBy('savedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(SavedServiceEntry.fromDoc).toList());
  }

}

class SavedServiceEntry {
  final String serviceId;
  final DateTime? savedAt;

  const SavedServiceEntry({
    required this.serviceId,
    required this.savedAt,
  });

  static SavedServiceEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return SavedServiceEntry(
      serviceId: (data['serviceId'] ?? doc.id).toString(),
      savedAt: (data['savedAt'] is Timestamp)
          ? (data['savedAt'] as Timestamp).toDate()
          : null,
    );
  }
}



