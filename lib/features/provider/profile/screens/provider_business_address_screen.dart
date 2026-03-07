import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/theme.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/screens/map_picker_screen.dart';
import 'package:geocoding/geocoding.dart' as geo;
import '../../../../core/utils/app_snack.dart';
import '../../../../core/utils/geohash.dart';
import '../../../../core/utils/kl_region_validator.dart';

class ProviderBusinessAddressScreen extends StatefulWidget {
  const ProviderBusinessAddressScreen({super.key});

  @override
  State<ProviderBusinessAddressScreen> createState() => _ProviderBusinessAddressScreenState();
}

class _ProviderBusinessAddressScreenState extends State<ProviderBusinessAddressScreen> {
  final ctrl = TextEditingController();
  bool loading = true;
  bool saving = false;

  double? businessLat;
  double? businessLng;
  String? businessGeohash;
  LatLng? _lastLatLng;
  bool pinned = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => loading = false);
      return;
    }

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final m = doc.data() ?? {};

    ctrl.text = (m['businessAddress'] ?? '').toString();

    businessLat = (m['businessLat'] as num?)?.toDouble();
    businessLng = (m['businessLng'] as num?)?.toDouble();
    businessGeohash = (m['businessGeohash'] ?? '').toString();

    pinned = businessLat != null && businessLng != null && (businessGeohash ?? '').trim().isNotEmpty;
    _lastLatLng = pinned ? LatLng(businessLat!, businessLng!) : null;

    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final addr = ctrl.text.trim();
    if (addr.isEmpty) {
      AppSnack.show(
        context,
        "Please enter your business address.",
        type: AppSnackType.error,
      );
      return;
    }

    if (!pinned || businessLat == null || businessLng == null || (businessGeohash ?? '').trim().isEmpty) {
      AppSnack.show(
        context,
        "Please pin your business location first.",
        type: AppSnackType.error,
      );
      return;
    }

    final check = await KlRegionValidator.validateLatLng(businessLat!, businessLng!);
    if (!check.ok) {
      if (!mounted) return;
      AppSnack.show(context, check.message, type: AppSnackType.error);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'businessAddress': ctrl.text.trim(),
        'businessLat': businessLat,
        'businessLng': businessLng,
        'businessGeohash': businessGeohash,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      AppSnack.show(context, "Business address saved", type: AppSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(context, "Save failed", type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _fillAddressFromPin(double lat, double lng) async {
    try {
      final placemarks = await geo.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return;

      final p = placemarks.first;

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
        final key = t.toLowerCase();
        if (seen.add(key)) parts.add(t);
      }

      final pretty = parts.join(", ");
      if (pretty.isNotEmpty) ctrl.text = pretty;
    } catch (_) {}
  }

  Future<void> _pickBusinessPin() async {
    final init = _lastLatLng ?? const LatLng(3.1390, 101.6869);

    final result = await Navigator.push<MapPickResult>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerScreen(initial: init)),
    );

    if (result == null) return;

    final check = await KlRegionValidator.validateLatLng(result.lat, result.lng);
    if (!check.ok) {
      if (!mounted) return;
      AppSnack.show(context, check.message, type: AppSnackType.error);
      return;
    }

    setState(() {
      businessLat = result.lat;
      businessLng = result.lng;
      businessGeohash = result.geohash;
      _lastLatLng = LatLng(result.lat, result.lng);
      pinned = true;
    });

    final formatted = (result.formattedAddress ?? '').trim();
    if (formatted.isNotEmpty) {
      ctrl.text = formatted;
    } else {
      await _fillAddressFromPin(result.lat, result.lng);
    }
  }

  Future<void> _pinFromAddress() async {
    final addr = ctrl.text.trim();
    if (addr.isEmpty) {
      AppSnack.show(
        context,
        "Please enter an address first.",
        type: AppSnackType.error,
      );
      return;
    }

    setState(() => saving = true);

    try {
      final locations = await geo.locationFromAddress(addr);
      if (locations.isEmpty) {
        if (!mounted) return;
        AppSnack.show(
          context,
          "Could not find this address. Try adding postcode/city.",
          type: AppSnackType.error,
        );
        return;
      }

      final loc = locations.first;
      final lat = loc.latitude;
      final lng = loc.longitude;

      final check = await KlRegionValidator.validateLatLng(lat, lng);
      if (!check.ok) {
        if (!mounted) return;
        AppSnack.show(context, check.message, type: AppSnackType.error);
        return;
      }

      final gh = GeoHash.encode(lat, lng, precision: 9);

      if (!mounted) return;
      setState(() {
        businessLat = lat;
        businessLng = lng;
        businessGeohash = gh;
        _lastLatLng = LatLng(lat, lng);
        pinned = true;
      });

      AppSnack.show(
        context,
        "Pin generated from address. Review it on map if needed.",
        type: AppSnackType.info,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        "Failed to locate address. Please try again.",
        type: AppSnackType.error,
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            children: [
              _TopBar(title: "Business Address", onBack: () => Navigator.pop(context)),
              const SizedBox(height: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: KLPalette.bg,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                          const Text("Address", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: ctrl,
                            maxLines: 6,
                            decoration: InputDecoration(
                              hintText: "Enter your business address",
                              prefixIcon: Icon(Icons.place_outlined),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: KLPalette.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: KLPalette.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: KLPalette.primary, width: 2),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton.tonal(
                                    onPressed: saving ? null : _pinFromAddress,
                                    child: const Text("Auto Pin", textAlign: TextAlign.center,),),
                                  ),
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton.tonal(
                                    onPressed: saving ? null : _pickBusinessPin,
                                    child: Text(pinned ? "Change Pin" : "Pick Pin"),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 8),
                          
                          Text(
                            pinned
                                ? "Pinned • ${businessLat!.toStringAsFixed(5)}, ${businessLng!.toStringAsFixed(5)}"
                                : "No pin yet",
                            style: const TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
                          ),

                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: saving ? null : _save,
                              child: saving
                                  ? const SizedBox(
                                height: 22, width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                                  : const Text("Save", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ),
                          ),
                                                ],
                                              ),
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: KLPalette.mutedBg,
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: const Icon(Icons.arrow_back, color: KLPalette.text),
          ),
        ),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}