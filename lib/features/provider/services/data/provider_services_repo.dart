import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp_flutter/core/utils/geohash.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

enum ServiceStatus { active, inactive }
enum ServiceType { onsite, remote }

class ProviderServiceUi {
  final String id;
  final String providerId;

  final String name;
  final String category;
  final String address;
  final ServiceType type;
  final ServiceStatus status;
  final bool autoLockTimeSlots;

  final List<String> photoUrls;
  final String? thumbnailUrl;

  final double price;
  final double discount;
  final List<Map<String, dynamic>> pricingRules;
  final Map<String, dynamic>? pricingCaps;
  final double hourlyRate;
  final int durationHours;
  final int durationMins;
  final String description;
  final bool featured;

  final double ratingAvg;
  final int ratingCount;

  final double? lat;
  final double? lng;
  final String? geohash;
  final bool isDeleted;
  final DateTime? deletedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProviderServiceUi({
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
    this.pricingRules = const [],
    this.pricingCaps,
    required this.hourlyRate,
    required this.durationHours,
    required this.durationMins,
    required this.description,
    required this.featured,
    this.ratingAvg = 0.0,
    this.ratingCount = 0,
    this.lat,
    this.lng,
    this.geohash,
    this.isDeleted = false,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  ProviderServiceUi copyWith({
    String? id,
    String? providerId,
    String? name,
    String? category,
    String? address,
    ServiceType? type,
    ServiceStatus? status,
    bool? autoLockTimeSlots,
    List<String>? photoUrls,
    String? thumbnailUrl,
    double? price,
    double? discount,
    List<Map<String, dynamic>>? pricingRules,
    Map<String, dynamic>? pricingCaps,
    double? hourlyRate,
    int? durationHours,
    int? durationMins,
    String? description,
    bool? featured,
    double? ratingAvg,
    int? ratingCount,
    double? lat,
    double? lng,
    String? geohash,
    bool? isDeleted,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProviderServiceUi(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      name: name ?? this.name,
      category: category ?? this.category,
      address: address ?? this.address,
      type: type ?? this.type,
      status: status ?? this.status,
      autoLockTimeSlots: autoLockTimeSlots ?? this.autoLockTimeSlots,
      photoUrls: photoUrls ?? this.photoUrls,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      price: price ?? this.price,
      discount: discount ?? this.discount,
      pricingRules: pricingRules ?? this.pricingRules,
      pricingCaps: pricingCaps ?? this.pricingCaps,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      durationHours: durationHours ?? this.durationHours,
      durationMins: durationMins ?? this.durationMins,
      description: description ?? this.description,
      featured: featured ?? this.featured,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      geohash: geohash ?? this.geohash,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "providerId": providerId,
      "name": name,
      "category": category,
      "address": address,
      "type": type.name,
      "status": status.name,
      "autoLockTimeSlots": autoLockTimeSlots,
      "photoUrls": photoUrls,
      "thumbnailUrl": thumbnailUrl,
      "price": price,
      "discount": discount,
      "pricingRules": _firestoreSafe(pricingRules),
      "pricingCaps": _firestoreSafe(pricingCaps),
      "hourlyRate": hourlyRate,
      "durationHours": durationHours,
      "durationMins": durationMins,
      "description": description,
      "featured": featured,
      "ratingAvg": ratingAvg,
      "ratingCount": ratingCount,
      "lat": lat,
      "lng": lng,
      "geohash": geohash,
      "isDeleted": isDeleted,
      "deletedAt": deletedAt,
    };
  }

  static ProviderServiceUi fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      SnapshotOptions? _,
      ) {
    final d = doc.data() ?? {};

    final photoUrls = (d["photoUrls"] as List?)
        ?.map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList() ??
        const <String>[];
    final thumbRaw = (d["thumbnailUrl"] ?? "").toString().trim();
    final thumbnailUrl = thumbRaw.isEmpty ? null : thumbRaw;

    final rulesRaw = d["pricingRules"];
    final rules = (rulesRaw is List)
        ? rulesRaw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList()
        : <Map<String, dynamic>>[];

    final capsRaw = d["pricingCaps"];
    final caps = (capsRaw is Map) ? capsRaw.cast<String, dynamic>() : null;

    final ratingAvg = (d["ratingAvg"] is num)
        ? (d["ratingAvg"] as num).toDouble()
        : ((d["rating"] is num) ? (d["rating"] as num).toDouble() : 0.0);

    final ratingCount = (d["ratingCount"] is num) ? (d["ratingCount"] as num).toInt() : 0;

    ServiceType parseType(String? s) => s == "remote" ? ServiceType.remote : ServiceType.onsite;
    ServiceStatus parseStatus(String? s) => s == "inactive" ? ServiceStatus.inactive : ServiceStatus.active;

    DateTime? tsToDt(dynamic v) => (v is Timestamp) ? v.toDate() : null;

    final isDeleted = (d["isDeleted"] ?? false) as bool;
    final deletedAt = tsToDt(d["deletedAt"]);

    return ProviderServiceUi(
      id: doc.id,
      providerId: (d["providerId"] ?? "") as String,
      name: (d["name"] ?? "") as String,
      category: (d["category"] ?? "") as String,
      address: (d["address"] ?? "") as String,
      type: parseType(d["type"] as String?),
      status: parseStatus(d["status"] as String?),
      autoLockTimeSlots: (d["autoLockTimeSlots"] ?? true) == true,
      photoUrls: photoUrls,
      thumbnailUrl: thumbnailUrl,
      price: (d["price"] is num) ? (d["price"] as num).toDouble() : 0,
      discount: (d["discount"] is num) ? (d["discount"] as num).toDouble() : 0,
      pricingRules: rules,
      pricingCaps: caps,
      hourlyRate: (d["hourlyRate"] is num) ? (d["hourlyRate"] as num).toDouble() : 0,
      durationHours: (d["durationHours"] is num) ? (d["durationHours"] as num).toInt() : 0,
      durationMins: (d["durationMins"] is num) ? (d["durationMins"] as num).toInt() : 0,
      description: (d["description"] ?? "") as String,
      featured: (d["featured"] ?? false) as bool,
      ratingAvg: ratingAvg,
      ratingCount: ratingCount,
      lat: (d["lat"] is num) ? (d["lat"] as num).toDouble() : null,
      lng: (d["lng"] is num) ? (d["lng"] as num).toDouble() : null,
      geohash: (d["geohash"] ?? "") == "" ? null : (d["geohash"] ?? "").toString(),
      isDeleted: isDeleted,
      deletedAt: deletedAt,
      createdAt: tsToDt(d["createdAt"]),
      updatedAt: tsToDt(d["updatedAt"]),
    );
  }
}

class ProviderServicesRepo {
  ProviderServicesRepo({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  CollectionReference<ProviderServiceUi> get _col =>
      _db.collection("services").withConverter<ProviderServiceUi>(
        fromFirestore: ProviderServiceUi.fromFirestore,
        toFirestore: (m, _) => m.toFirestore(),
      );

  String get uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError("Not authenticated");
    return u.uid;
  }

  Stream<List<ProviderServiceUi>> watchMyServices() {
    return _col
        .where("providerId", isEqualTo: uid)
        .where("isDeleted", isEqualTo: false)
        .orderBy("updatedAt", descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<ProviderServiceUi> createService(ProviderServiceUi draft) async {
    final doc = (draft.id.isNotEmpty) ? _col.doc(draft.id) : _col.doc();
    ProviderServiceUi data = draft.copyWith(
      id: doc.id,
      providerId: uid,
      ratingAvg: 0.0,
      ratingCount: 0,
      isDeleted: false,
    );

    data = await _ensureLatLngGeohash(data);

    await doc.set(data);

    await doc.update({
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    });

    final fresh = await doc.get();
    return fresh.data()!;
  }


  Future<ProviderServiceUi> updateService(ProviderServiceUi s) async {
    final doc = _col.doc(s.id);

    ProviderServiceUi data = s;

    data = await _ensureLatLngGeohash(data);

    await doc.update({
      "name": data.name,
      "category": data.category,
      "address": data.address,
      "type": data.type.name,
      "status": data.status.name,
      "autoLockTimeSlots": data.autoLockTimeSlots,
      "photoUrls": data.photoUrls,
      "thumbnailUrl": data.thumbnailUrl,
      "price": data.price,
      "discount": data.discount,
      "pricingRules": _firestoreSafe(data.pricingRules),
      "pricingCaps": _firestoreSafe(data.pricingCaps),
      "hourlyRate": data.hourlyRate,
      "durationHours": data.durationHours,
      "durationMins": data.durationMins,
      "description": data.description,
      "featured": data.featured,
      "lat": data.lat,
      "lng": data.lng,
      "geohash": data.geohash,
      "updatedAt": FieldValue.serverTimestamp(),
    });

    final fresh = await doc.get();
    return fresh.data()!;
  }

  Future<void> hardDeleteService(String serviceId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not logged in");

    await FirebaseFirestore.instance
        .collection('services')
        .doc(serviceId)
        .delete();
  }

  Future<void> safeDeleteService(String serviceId) async {
    final hasUpcoming = await hasUpcomingBookingsForService(serviceId);
    if (hasUpcoming) {
      throw StateError("HAS_UPCOMING_BOOKINGS");
    }

    final doc = _col.doc(serviceId);

    await doc.update({
      "isDeleted": true,
      "status": ServiceStatus.inactive.name,
      "deletedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  Future<bool> hasUpcomingBookingsForService(String serviceId) async {
    final now = Timestamp.fromDate(DateTime.now());

    final q = await _db
        .collection('bookings')
        .where('providerId', isEqualTo: uid)
        .where('serviceId', isEqualTo: serviceId)
        .where('status', whereIn: ['pending', 'accepted'])
        .where('scheduledAt', isGreaterThanOrEqualTo: now)
        .limit(1)
        .get();

    return q.docs.isNotEmpty;
  }


  String _encodeGeohash(double lat, double lng) {
    return GeoHash.encode(lat, lng, precision: 9);
  }

  Future<ProviderServiceUi> _ensureLatLngGeohash(ProviderServiceUi data) async {
    ProviderServiceUi out = data;

    // If no pin, try geocode from typed address
    if (out.lat == null || out.lng == null) {
      final addr = out.address.trim();
      if (addr.isNotEmpty) {
        try {
          final locs = await locationFromAddress(addr);
          if (locs.isNotEmpty) {
            final lat = locs.first.latitude;
            final lng = locs.first.longitude;
            out = out.copyWith(
              lat: lat,
              lng: lng,
              geohash: _encodeGeohash(lat, lng),
            );
          }
        } catch (_) {

        }
      }
    }

    // If lat/lng exists but geohash missing, generate geohash
    if (out.geohash == null && out.lat != null && out.lng != null) {
      out = out.copyWith(geohash: _encodeGeohash(out.lat!, out.lng!));
    }

    return out;
  }

  String newServiceId() => _col.doc().id;

  String _contentTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<List<String>> uploadServicePhotos({
    required String serviceId,
    required List<XFile> files,
  }) async {
    if (files.isEmpty) return const [];

    final out = <String>[];
    for (final f in files) {
      final fileName = "${_uuid.v4()}_${f.name}";
      final ref = _storage.ref().child("services/$serviceId/photos/$fileName");

      final bytes = await f.readAsBytes();
      final meta = SettableMetadata(contentType: _contentTypeFromName(f.name));

      final snap = await ref.putData(bytes, meta);
      final url = await snap.ref.getDownloadURL();
      out.add(url);
    }
    return out;
  }

}

dynamic _firestoreSafe(dynamic v) {
  if (v == null) return null;

  if (v is DateTime) return v;
  if (v is Timestamp) return v;

  if (v is num || v is bool || v is String) return v;

  if (v is List) {
    return v.map(_firestoreSafe).toList();
  }

  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _firestoreSafe(val)));
  }

  // Fallback: stringify unsupported types
  return v.toString();
}
