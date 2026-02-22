import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

import 'theme.dart';
import 'geohash.dart';

class MapPickResult {
  final double lat;
  final double lng;
  final String geohash;
  final String? formattedAddress;

  const MapPickResult({
    required this.lat,
    required this.lng,
    required this.geohash,
    this.formattedAddress,
  });
}

class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;

  const MapPickerScreen({super.key, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _controller;
  LatLng _center = const LatLng(3.1390, 101.6869); // KL default
  bool _loadingLocation = false;
  String? _prettyAddress;
  bool _resolving = false;
  DateTime? _lastResolveAt;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _center = widget.initial!;
    _tryMoveToUser();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveAddress(_center, force: true);
    });
  }

  Future<void> _resolveAddress(LatLng p, {bool force = false}) async {
    // resolve at most once per ~800ms unless forced
    final now = DateTime.now();
    if (!force && _lastResolveAt != null && now.difference(_lastResolveAt!).inMilliseconds < 800) {
      return;
    }
    _lastResolveAt = now;

    if (mounted) setState(() => _resolving = true);

    try {
      final placemarks = await geo.placemarkFromCoordinates(p.latitude, p.longitude);
      if (placemarks.isEmpty) return;

      final pm = placemarks.first;

      final rawParts = <String?>[
        pm.name,
        pm.street,
        pm.subLocality,
        pm.locality,
        pm.postalCode,
        pm.administrativeArea,
        pm.country,
      ];

      final seen = <String>{};
      final parts = <String>[];

      for (final s in rawParts) {
        final t = (s ?? '').trim();
        if (t.isEmpty) continue;

        final key = t.toLowerCase();
        if (seen.add(key)) {
          parts.add(t);
        }
      }

      final pretty = parts.join(", ");

      if (!mounted) return;
      setState(() => _prettyAddress = pretty.isEmpty ? null : pretty);
    } catch (_) {

    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }


  Future<void> _tryMoveToUser() async {
    setState(() => _loadingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final target = LatLng(pos.latitude, pos.longitude);
      setState(() => _center = target);

      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      await _resolveAddress(target, force: true);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _confirm() {
    final gh = GeoHash.encode(_center.latitude, _center.longitude, precision: 9);
    Navigator.pop(
      context,
      MapPickResult(
        lat: _center.latitude,
        lng: _center.longitude,
        geohash: gh,
        formattedAddress: _prettyAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  _CircleBtn(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  const Text("Pinpoint Location",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const Spacer(),
                  _CircleBtn(
                    icon: Icons.my_location,
                    onTap: _tryMoveToUser,
                    loading: _loadingLocation,
                  ),
                ],
              ),
            ),

            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(target: _center, zoom: 15),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      onMapCreated: (c) => _controller = c,
                      onCameraMove: (pos) => _center = pos.target,
                      onCameraIdle: () => _resolveAddress(_center),
                    ),

                    // Center pin overlay
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: Icon(Icons.location_on, size: 44, color: KLPalette.primary),
                      ),
                    ),

                    // small “info card”
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 18,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            border: Border.all(color: KLPalette.border),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              Container(
                                height: 44,
                                width: 44,
                                decoration: BoxDecoration(
                                  color: KLPalette.tint50,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: KLPalette.border),
                                ),
                                child: const Icon(Icons.place, color: KLPalette.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _resolving
                                      ? "Looking up address...\nLat: ${_center.latitude.toStringAsFixed(5)}  Lng: ${_center.longitude.toStringAsFixed(5)}"
                                      : "${_prettyAddress ?? "Move the map to place the pin."}\nLat: ${_center.latitude.toStringAsFixed(5)}  Lng: ${_center.longitude.toStringAsFixed(5)}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: KLPalette.text2,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 44,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: KLPalette.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  ),
                                  onPressed: _confirm,
                                  child: const Text("Confirm",
                                      style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  const _CircleBtn({
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: KLPalette.mutedBg,
          shape: BoxShape.circle,
          border: Border.all(color: KLPalette.border),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : Icon(icon, color: KLPalette.text),
        ),
      ),
    );
  }
}