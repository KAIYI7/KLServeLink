import 'address_firestore.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'address_select_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_picker_screen.dart';
import 'geohash.dart';

class YourAddressScreen extends StatefulWidget {
  final AddressUiModel initial;

  const YourAddressScreen({super.key, required this.initial});

  @override
  State<YourAddressScreen> createState() => _YourAddressScreenState();
}

class _YourAddressScreenState extends State<YourAddressScreen> {
  late AddressUiModel selected;
  GoogleMapController? _mapController;
  bool _movedToUserOnce = false;

  final _fs = AddressFirestore();

  @override
  void initState() {
    super.initState();
    selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final center = (selected.lat != null && selected.lng != null)
        ? LatLng(selected.lat!, selected.lng!)
        : const LatLng(3.1390, 101.6869); // KL fallback

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            children: [
              _TopBar(
                title: "Your Address",
                onBack: () => Navigator.pop(context),
                onMenu: () {},
              ),
              const SizedBox(height: 14),

              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: SizedBox(
                  height: 260,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(target: center, zoom: 15),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        onMapCreated: (c) {
                          _mapController = c;
                          _moveToUserIfNoPin();
                        },
                        markers: {
                          Marker(
                            markerId: const MarkerId("address"),
                            position: center,
                          ),
                        },
                        onTap: (_) async {
                          await _repinLocation(context);

                          if (selected.lat != null && selected.lng != null) {
                            await _mapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(LatLng(selected.lat!, selected.lng!), 16),
                            );
                          }
                        },
                      ),

                      // Center hint (optional)
                      Positioned(
                        left: 14,
                        top: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: KLPalette.border),
                          ),
                          child: const Text(
                            "Tap map to repin",
                            style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // My Address card
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: KLPalette.bg,
                    border: Border.all(color: KLPalette.border),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text("My Address",
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26)),
                          const Spacer(),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: KLPalette.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            onPressed: () async {
                              final result = await Navigator.push<AddressUiModel>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddressSelectScreen(initial: selected),
                                ),
                              );
                              if (result != null) setState(() => selected = result);

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _moveCameraToSelected();
                              });
                            },
                            icon: const Icon(Icons.edit, size: 15, color: KLPalette.text),
                            label: const Text("Edit",
                                style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text)),
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 44,
                            width: 44,
                            decoration: BoxDecoration(
                              color: KLPalette.mutedBg,
                              shape: BoxShape.circle,
                              border: Border.all(color: KLPalette.border),
                            ),
                            child: const Icon(Icons.location_on_outlined, color: KLPalette.text),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(selected.title,
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                                const SizedBox(height: 6),
                                Text(
                                  selected.addressLine,
                                  style: const TextStyle(
                                    color: KLPalette.text2,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KLPalette.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: () {
                    Navigator.pop(context, selected);
                  },
                  child: const Text("Continue",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _repinLocation(BuildContext context) async {
    final init = (selected.lat != null && selected.lng != null)
        ? LatLng(selected.lat!, selected.lng!)
        : const LatLng(3.1390, 101.6869);

    final result = await Navigator.push<MapPickResult>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerScreen(initial: init)),
    );

    if (result == null) return;

    setState(() {
      selected = selected.copyWith(
        lat: result.lat,
        lng: result.lng,
        geohash: result.geohash,
        addressLine: (result.formattedAddress ?? selected.addressLine),
      );
    });

    if (selected.id.isNotEmpty) {
      await _fs.updatePin(
        addressId: selected.id,
        lat: result.lat,
        lng: result.lng,
        geohash: result.geohash,
      );

      if (result.formattedAddress != null && result.formattedAddress!.trim().isNotEmpty) {
        await _fs.updateAddressLine(
          addressId: selected.id,
          addressLine: result.formattedAddress!,
        );
      }
    }
  }

  Future<void> _moveToUserIfNoPin() async {
    if (selected.lat != null && selected.lng != null) return;
    if (_movedToUserOnce) return;

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

      _movedToUserOnce = true;

      final target = LatLng(pos.latitude, pos.longitude);

      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(target, 16),
      );
    } catch (_) {

    }
  }

  Future<void> _moveCameraToSelected() async {
    if (_mapController == null) return;
    if (selected.lat == null || selected.lng == null) return;

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(selected.lat!, selected.lng!),
        16,
      ),
    );
  }

}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onMenu;

  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back, onTap: onBack),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const Spacer(),
        _CircleButton(icon: Icons.more_horiz, onTap: onMenu),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: KLPalette.mutedBg,
          shape: BoxShape.circle,
          border: Border.all(color: KLPalette.border),
        ),
        child: Icon(icon, color: KLPalette.text),
      ),
    );
  }
}

/// Shared model used across address screens
class AddressUiModel {
  final String id;
  final String title;
  final String addressLine;
  final String contactName;
  final String contactPhone;
  final String addressType;
  final bool isMain;
  final double? lat;
  final double? lng;
  final String? geohash;

  AddressUiModel({
    required this.id,
    required this.title,
    required this.addressLine,
    this.contactName = "",
    this.contactPhone = "",
    this.addressType = "Home",
    this.isMain = false,
    this.lat,
    this.lng,
    this.geohash,

  });

  AddressUiModel copyWith({
    String? id,
    String? title,
    String? addressLine,
    String? contactName,
    String? contactPhone,
    String? addressType,
    bool? isMain,
    double? lat,
    double? lng,
    String? geohash,
  }) {
    return AddressUiModel(
      id: id ?? this.id,
      title: title ?? this.title,
      addressLine: addressLine ?? this.addressLine,
      contactName: contactName ?? this.contactName,
      contactPhone: contactPhone ?? this.contactPhone,
      addressType: addressType ?? this.addressType,
      isMain: isMain ?? this.isMain,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      geohash: geohash ?? this.geohash,
    );
  }

  factory AddressUiModel.demoHome() {
    return AddressUiModel(
      id: "home",
      title: "My Home",
      addressLine: "Kuala Lumpur, Malaysia (Default address)",
      contactName: "Lee Kai Yi",
      contactPhone: "+60 12-345 6789",
      addressType: "Home",
      isMain: true,
    );
  }
}