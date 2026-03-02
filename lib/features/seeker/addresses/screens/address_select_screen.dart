import '../data/address_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import '../../../../core/utils/geohash.dart';
import '../../../../core/screens/map_picker_screen.dart';
import '../../../../core/theme/theme.dart';
import 'your_address_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AddressSelectScreen extends StatefulWidget {
  final AddressUiModel initial;

  const AddressSelectScreen({super.key, required this.initial});

  @override
  State<AddressSelectScreen> createState() => _AddressSelectScreenState();
}

class _AddressSelectScreenState extends State<AddressSelectScreen> {
  late AddressUiModel selected;
  final _fs = AddressFirestore();

  @override
  void initState() {
    super.initState();
    selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            children: [
              _TopBar(
                title: "My Address",
                onBack: () => Navigator.pop(context),
              ),
              const SizedBox(height: 14),

              Expanded(
                child: StreamBuilder<List<AddressUiModel>>(
                  stream: _fs.streamAddresses(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final addresses = snap.data ?? const [];

                    return ListView.separated(
                      itemCount: addresses.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == addresses.length) {
                          return _AddNewAddressButton(
                            onTap: () async {
                              final created = await _showAddAddressSheet(context);
                              if (created == null) return;

                              final id = await _fs.upsertAddress(model: created);

                              setState(() {
                                selected = created.copyWith(id: id);
                              });
                            },
                          );
                        }

                        final a = addresses[i];
                        final isSelected = a.id == selected.id;

                        return _AddressCard(
                          address: a,
                          selected: isSelected,
                          onTap: () => setState(() => selected = a),
                          onEdit: () async {
                            final updated = await _showAddAddressSheet(context, initial: a);
                            if (updated == null) return;

                            await _fs.upsertAddress(model: updated);
                            setState(() => selected = updated);
                          },

                          onDelete: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text("Delete address?"),
                                content: const Text("This cannot be undone."),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
                                ],
                              ),
                            );

                            if (ok != true) return;

                            await _fs.deleteAddressAndKeepMain(a.id);

                            if (selected.id == a.id) {
                              setState(() => selected = widget.initial);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KLPalette.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text("Confirm",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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

  const _TopBar({
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back, onTap: onBack),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const Spacer(),
        const SizedBox(width: 48),
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

class _AddressCard extends StatelessWidget {
  final AddressUiModel address;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AddressCard({
    required this.address,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? KLPalette.tint50 : KLPalette.bg;
    final border = selected ? KLPalette.primary : KLPalette.border;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    address.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
                  ),
                ),
                const SizedBox(width: 10),

                if (address.isMain)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: KLPalette.bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: border),
                    ),
                    child: const Text(
                      "Main Address",
                      style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary),
                    ),
                  ),

                const SizedBox(width: 4),

                PopupMenuButton<String>(
                  color: Colors.white,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (v) {
                    if (v == "edit") onEdit();
                    if (v == "delete") onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: "edit",
                      child: Row(
                        children: const [
                          Icon(Icons.edit, color: Colors.lightBlue, size: 18),
                          SizedBox(width: 8),
                          Text("Edit", style: TextStyle(color: KLPalette.text)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: "delete",
                      child: Row(
                        children: const [
                          Icon(Icons.delete, color: Colors.lightBlue, size: 18),
                          SizedBox(width: 8),
                          Text("Delete", style: TextStyle(color: KLPalette.text)),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KLPalette.bg,
                      border: Border.all(color: border),
                    ),
                    child: const Icon(Icons.more_horiz, color: KLPalette.text2),
                  ),
                ),

                const SizedBox(width: 4),
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? KLPalette.primary : KLPalette.bg,
                    border: Border.all(color: border),
                  ),
                  child: Icon(
                    Icons.check,
                    color: selected ? Colors.white : KLPalette.text2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "${address.contactName} | ${address.contactPhone}",
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              address.addressType,
              style: const TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
            ),
            const SizedBox(height: 8),
            Text(
              address.addressLine,
              style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  (address.lat != null && address.lng != null) ? Icons.place : Icons.place_outlined,
                  size: 18,
                  color: (address.lat != null && address.lng != null) ? KLPalette.primary : KLPalette.text2,
                ),
                const SizedBox(width: 8),
                Text(
                  (address.lat != null && address.lng != null)
                      ? "Pinpoint saved"
                      : "No pinpoint yet",
                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddNewAddressButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddNewAddressButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: const Center(
          child: Text(
            "+   Add New Address",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
      ),
    );
  }
}

Future<AddressUiModel?> _showAddAddressSheet(BuildContext context, {AddressUiModel? initial}) {
  return showModalBottomSheet<AddressUiModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: KLPalette.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _AddAddressSheet(initial: initial),
  );
}

class _AddAddressSheet extends StatefulWidget {
  final AddressUiModel? initial;
  const _AddAddressSheet({this.initial});

  @override
  State<_AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends State<_AddAddressSheet> {
  final _formKey = GlobalKey<FormState>();

  final _labelCtrl = TextEditingController(text: "");
  final _nameCtrl = TextEditingController(text: "");
  final _phoneCtrl = TextEditingController(text: "+60");
  final _addrCtrl = TextEditingController();

  bool isMain = false;
  bool pinned = false;

  String type = "Home"; // Home / Apartment / Office / Other

  double? _pickedLat;
  double? _pickedLng;
  String? _pickedGeohash;

  LatLng? _lastLatLng;

  @override
  void initState() {
    super.initState();

    final a = widget.initial;
    if (a != null) {
      _labelCtrl.text = a.title;
      _nameCtrl.text = a.contactName;
      _phoneCtrl.text = a.contactPhone;
      _addrCtrl.text = a.addressLine;

      isMain = a.isMain;
      type = a.addressType;

      pinned = (a.lat != null && a.lng != null && (a.geohash ?? "").isNotEmpty);
      _pickedLat = a.lat;
      _pickedLng = a.lng;
      _pickedGeohash = a.geohash;
      if (a.lat != null && a.lng != null) {
        _lastLatLng = LatLng(a.lat!, a.lng!);
      }
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
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
        if (seen.add(key)) {
          parts.add(t);
        }
      }

      final pretty = parts.join(", ");
      if (pretty.isNotEmpty) {
        _addrCtrl.text = pretty;
      }
    } catch (_) {

    }
  }


  Future<void> _locateFromTypedAddress() async {
    final text = _addrCtrl.text.trim();
    if (text.isEmpty) return;

    try {
      final locs = await geo.locationFromAddress(text);
      if (locs.isEmpty) return;

      final lat = locs.first.latitude;
      final lng = locs.first.longitude;
      final gh = GeoHash.encode(lat, lng, precision: 9);

      setState(() {
        pinned = true;
        _pickedLat = lat;
        _pickedLng = lng;
        _pickedGeohash = gh;
        _lastLatLng = LatLng(lat, lng);
      });

      // Let user confirm/adjust on map
      final result = await Navigator.push<MapPickResult>(
        context,
        MaterialPageRoute(
          builder: (_) => MapPickerScreen(initial: LatLng(lat, lng)),
        ),
      );

      if (result == null) return;

      setState(() {
        pinned = true;
        _pickedLat = result.lat;
        _pickedLng = result.lng;
        _pickedGeohash = result.geohash;
        _lastLatLng = LatLng(result.lat, result.lng);
      });

      if ((result.formattedAddress ?? "").trim().isNotEmpty) {
        _addrCtrl.text = result.formattedAddress!.trim();
      } else {
        await _fillAddressFromPin(result.lat, result.lng);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn’t locate that address. Try adding postcode/city.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 4,
            width: 46,
            decoration: BoxDecoration(
              color: KLPalette.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              const Text(
                "Add New Address",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Form(
            key: _formKey,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Address Type",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: KLPalette.text2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: ["Home", "Apartment", "Office", "Other"].map((t) {
                    final selected = t == type;
                    return _PillChip(
                      label: t,
                      selected: selected,
                      onTap: () => setState(() => type = t),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),

                _Field(
                  label: "Label",
                  hint: "e.g. My Home",
                  controller: _labelCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Enter a label" : null,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        label: "Contact Name",
                        hint: "Full name",
                        controller: _nameCtrl,
                        validator: (v) => (v == null || v.trim().isEmpty) ? "Enter name" : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        label: "Phone",
                        hint: "+60...",
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().length < 6) ? "Enter phone" : null,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _Field(
                  label: "Full Address",
                  hint: "Street, area, postcode, Kuala Lumpur",
                  controller: _addrCtrl,
                  maxLines: 3,
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Enter address" : null,
                ),

                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: KLPalette.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: _locateFromTypedAddress,
                    icon: const Icon(Icons.my_location, color: KLPalette.text),
                    label: const Text(
                      "Locate on map",
                      style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Pinpoint
                InkWell(
                  onTap: () async {
                    final result = await Navigator.push<MapPickResult>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapPickerScreen(
                          initial: (_lastLatLng != null) ? _lastLatLng : null,
                        ),
                      ),
                    );

                    if (result == null) return;

                    setState(() {
                      pinned = true;
                      _pickedLat = result.lat;
                      _pickedLng = result.lng;
                      _pickedGeohash = result.geohash;
                      _lastLatLng = LatLng(result.lat, result.lng);
                    });

                    if ((result.formattedAddress ?? "").trim().isNotEmpty) {
                      _addrCtrl.text = result.formattedAddress!.trim();
                    } else {
                      await _fillAddressFromPin(result.lat, result.lng);
                    }
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: KLPalette.mutedBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: KLPalette.bg,
                            shape: BoxShape.circle,
                            border: Border.all(color: KLPalette.border),
                          ),
                          child: Icon(
                            pinned ? Icons.check_circle : Icons.my_location,
                            color: pinned ? KLPalette.primary : KLPalette.text2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Pinpoint Location",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                              const SizedBox(height: 4),

                              if (pinned && _pickedLat != null && _pickedLng != null && _pickedGeohash != null)
                                Text(
                                  "Pinned • ${_pickedLat!.toStringAsFixed(5)}, ${_pickedLng!.toStringAsFixed(5)}",
                                  style: const TextStyle(
                                    color: KLPalette.text2,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                )
                              else
                                const Text(
                                  "Tap to set location on map",
                                  style: TextStyle(
                                    color: KLPalette.text2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          pinned ? "Change" : "",
                          style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text2),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, color: KLPalette.text2),
                      ],
                    ),
                  ),
                ),


                const SizedBox(height: 10),

                // Main address toggle
                InkWell(
                  onTap: () => setState(() => isMain = !isMain),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: KLPalette.bg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isMain ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isMain ? KLPalette.primary : KLPalette.text2,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            "Set as Main Address",
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: KLPalette.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: () {
                      if (!(_formKey.currentState?.validate() ?? false)) return;

                      if (!pinned || _pickedLat == null || _pickedLng == null || _pickedGeohash == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Please pinpoint your location on the map.")),
                        );
                        return;
                      }

                      final title = _labelCtrl.text.trim();
                      final addr = _addrCtrl.text.trim();

                      final created = AddressUiModel(
                        id: widget.initial?.id ?? "",
                        title: title,
                        addressLine: addr,
                        contactName: _nameCtrl.text.trim(),
                        contactPhone: _phoneCtrl.text.trim(),
                        addressType: type,
                        isMain: isMain,
                        lat: _pickedLat,
                        lng: _pickedLng,
                        geohash: _pickedGeohash,
                      );

                      Navigator.pop(context, created);
                    },
                    child: const Text(
                      "Save Address",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? KLPalette.primary : KLPalette.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: KLPalette.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : KLPalette.text,
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final int maxLines;
  final TextInputType? keyboardType;

  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.validator,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text2)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: KLPalette.bg,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: KLPalette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: KLPalette.primary, width: 1.4),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}