import 'package:geocoding/geocoding.dart' as geo;

class KlRegionValidation {
  final bool ok;
  final String message;
  final String? formattedAddress;

  const KlRegionValidation({
    required this.ok,
    this.message = '',
    this.formattedAddress,
  });
}

class KlRegionValidator {
  // KL-area box.
  static const double _minLat = 3.00;
  static const double _maxLat = 3.26;
  static const double _minLng = 101.58;
  static const double _maxLng = 101.80;

  static bool isWithinKlBounds(double lat, double lng) {
    return lat >= _minLat &&
        lat <= _maxLat &&
        lng >= _minLng &&
        lng <= _maxLng;
  }

  static Future<KlRegionValidation> validateLatLng(
      double lat,
      double lng,
      ) async {
    if (!isWithinKlBounds(lat, lng)) {
      return const KlRegionValidation(
        ok: false,
        message: 'This location is outside Kuala Lumpur.',
      );
    }

    try {
      final placemarks = await geo.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) {
        return const KlRegionValidation(ok: true);
      }

      final p = placemarks.first;
      final fields = <String>[
        p.locality ?? '',
        p.subAdministrativeArea ?? '',
        p.administrativeArea ?? '',
        p.country ?? '',
      ].map((e) => e.toLowerCase()).toList();

      final looksLikeKl = fields.any((v) =>
      v.contains('kuala lumpur') ||
          v.contains('wilayah persekutuan'));

      final rawParts = <String?>[
        p.name,
        p.street,
        p.subLocality,
        p.locality,
        p.postalCode,
        p.administrativeArea,
        p.country,
      ];

      final seen = <String>{};
      final parts = <String>[];
      for (final s in rawParts) {
        final t = (s ?? '').trim();
        if (t.isEmpty) continue;
        if (seen.add(t.toLowerCase())) parts.add(t);
      }

      final pretty = parts.isEmpty ? null : parts.join(', ');

      if (!looksLikeKl) {
        return KlRegionValidation(
          ok: false,
          message: 'Please choose an address within Kuala Lumpur.',
          formattedAddress: pretty,
        );
      }

      return KlRegionValidation(
        ok: true,
        formattedAddress: pretty,
      );
    } catch (_) {
      // Bounds already passed, so allow it.
      return const KlRegionValidation(ok: true);
    }
  }
}