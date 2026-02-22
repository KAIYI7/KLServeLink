import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'your_address_screen.dart';

class AddressFirestore {
  final _db = FirebaseFirestore.instance;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError("Not authenticated");
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('addresses');

  Stream<List<AddressUiModel>> streamAddresses() {
    final uid = _uid;

    // Main first, then latest updated
    final q = _col(uid)
        .orderBy('isMain', descending: true)
        .orderBy('updatedAt', descending: true);

    return q.snapshots().map((snap) {
      return snap.docs.map((d) {
        final m = d.data();
        return AddressUiModel(
          id: d.id,
          title: (m['title'] ?? 'My Address').toString(),
          addressLine: (m['addressLine'] ?? '').toString(),
          contactName: (m['contactName'] ?? '').toString(),
          contactPhone: (m['contactPhone'] ?? '').toString(),
          addressType: (m['addressType'] ?? 'Home').toString(),
          isMain: (m['isMain'] ?? false) == true,
          lat: (m['lat'] is num) ? (m['lat'] as num).toDouble() : null,
          lng: (m['lng'] is num) ? (m['lng'] as num).toDouble() : null,
          geohash: (m['geohash'] ?? '') == '' ? null : (m['geohash'] ?? '').toString(),
        );
      }).toList();
    });
  }

  /// Create or update address doc.
  /// If isMain == true, ensures only this doc stays main.
  Future<String> upsertAddress({
    required AddressUiModel model,
  }) async {
    final uid = _uid;

    // generate doc id if empty
    final docRef = (model.id.isEmpty) ? _col(uid).doc() : _col(uid).doc(model.id);

    final batch = _db.batch();

    if (model.isMain) {
      final othersSnap =
      await _col(uid).where('isMain', isEqualTo: true).get();

      for (final d in othersSnap.docs) {
        if (d.id == docRef.id) continue;
        batch.update(d.reference, {
          'isMain': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    final data = <String, dynamic>{
      'title': model.title,
      'addressLine': model.addressLine,
      'contactName': model.contactName,
      'contactPhone': model.contactPhone,
      'addressType': model.addressType,
      'isMain': model.isMain,
      'lat': model.lat,
      'lng': model.lng,
      'geohash': model.geohash,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (model.id.isEmpty) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    batch.set(docRef, data, SetOptions(merge: true));

    await batch.commit();
    return docRef.id;
  }

  Future<void> setMainAddress(String addressId) async {
    final uid = _uid;
    final docRef = _col(uid).doc(addressId);

    final batch = _db.batch();

    final mainsSnap =
    await _col(uid).where('isMain', isEqualTo: true).get();

    for (final d in mainsSnap.docs) {
      if (d.id == addressId) continue;
      batch.update(d.reference, {
        'isMain': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.update(docRef, {
      'isMain': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> updatePin({
    required String addressId,
    required double lat,
    required double lng,
    required String geohash,
  }) async {
    final uid = _uid;
    await _col(uid).doc(addressId).set({
      'lat': lat,
      'lng': lng,
      'geohash': geohash,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateAddressLine({
    required String addressId,
    required String addressLine,
  }) async {
    final uid = _uid;
    await _col(uid).doc(addressId).set({
      'addressLine': addressLine,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteAddress(String addressId) async {
    final uid = _uid;
    await _col(uid).doc(addressId).delete();
  }

  Future<void> deleteAddressAndKeepMain(String addressId) async {
    final uid = _uid;
    final col = _col(uid);

    final targetSnap = await col.doc(addressId).get();
    if (!targetSnap.exists) return;

    final wasMain = (targetSnap.data()?['isMain'] ?? false) == true;

    final batch = _db.batch();
    batch.delete(col.doc(addressId));

    // if deleted main, promote another one
    if (wasMain) {
      final candidates = await col
          .orderBy('updatedAt', descending: true)
          .limit(5)
          .get();

      // pick first doc that is not the deleted one
      DocumentSnapshot<Map<String, dynamic>>? pick;
      for (final d in candidates.docs) {
        if (d.id == addressId) continue;
        pick = d;
        break;
      }

      if (pick != null) {
        batch.update(pick.reference, {
          'isMain': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } else {
      // if after delete there is NO main at all, promote one
      final mains = await col.where('isMain', isEqualTo: true).limit(1).get();
      if (mains.docs.isEmpty) {
        final any = await col.orderBy('updatedAt', descending: true).limit(1).get();
        if (any.docs.isNotEmpty && any.docs.first.id != addressId) {
          batch.update(any.docs.first.reference, {
            'isMain': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }

    await batch.commit();
  }

}