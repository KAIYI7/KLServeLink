import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/your_address_screen.dart';

class SeekerAddressFirestore {
  final _db = FirebaseFirestore.instance;

  Stream<AddressUiModel?> streamMainAddress({required String uid}) {
    final q = _db
        .collection('users')
        .doc(uid)
        .collection('addresses')
        .orderBy('isMain', descending: true)
        .orderBy('updatedAt', descending: true)
        .limit(1);

    return q.snapshots().map((snap) {
      if (snap.docs.isEmpty) return null;

      final d = snap.docs.first;
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
    });
  }
}