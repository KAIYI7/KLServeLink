import 'package:fyp_flutter/pricing/dynamic_pricing_models.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'categories.dart';
import 'package:flutter/material.dart';
import 'dynamic_pricing_rules_editor_screen.dart';
import 'geohash.dart';
import 'theme.dart';
import 'data/provider_services_repo.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_picker_screen.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProviderServiceFormScreen extends StatefulWidget {
  final ProviderServiceUi? initial;

  const ProviderServiceFormScreen({super.key, this.initial});

  @override
  State<ProviderServiceFormScreen> createState() => _ProviderServiceFormScreenState();
}

class _ProviderServiceFormScreenState extends State<ProviderServiceFormScreen> {
  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final discountCtrl = TextEditingController();
  final hoursCtrl = TextEditingController();
  final minsCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final repo = ProviderServicesRepo();

  String? category;
  ServiceType type = ServiceType.onsite;
  ServiceStatus status = ServiceStatus.active;
  bool featured = false;
  double? serviceLat;
  double? serviceLng;
  String? serviceGeohash;
  LatLng? _lastLatLng;

  bool saving = false;
  String? errorText;

  final categories = kCategories.map((c) => c.label).toList();

  bool _addressDirty = false;
  String _lastGeocodedAddress = "";

  List<Map<String, dynamic>> _pricingRules = [];
  Map<String, dynamic>? _pricingCaps;

  final _picker = ImagePicker();

  List<String> _existingPhotoUrls = [];
  Set<String> _removedExistingUrls = {};

  final List<XFile> _newFiles = [];
  final List<Uint8List> _newBytes = [];

  String? _thumbExistingUrl;   // if thumbnail is one of existing urls
  int? _thumbNewIndex;         // if thumbnail is one of newly picked photos

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    if (s != null) {
      nameCtrl.text = s.name;
      priceCtrl.text = s.price.toStringAsFixed(0);
      discountCtrl.text = s.discount.toStringAsFixed(0);
      hoursCtrl.text = s.durationHours.toString();
      minsCtrl.text = s.durationMins.toString();
      descCtrl.text = s.description;
      addressCtrl.text = s.address;

      category = s.category;
      type = s.type;
      status = s.status;
      featured = s.featured;
      serviceLat = s.lat;
      serviceLng = s.lng;
      serviceGeohash = s.geohash;
      _lastLatLng = (serviceLat != null && serviceLng != null)
          ? LatLng(serviceLat!, serviceLng!)
          : null;

      _pricingRules = List<Map<String, dynamic>>.from(s.pricingRules);
      _pricingCaps = s.pricingCaps == null ? null : Map<String, dynamic>.from(s.pricingCaps!);
      _existingPhotoUrls = List<String>.from(s.photoUrls);
      _thumbExistingUrl = s.thumbnailUrl ?? (_existingPhotoUrls.isNotEmpty ? _existingPhotoUrls.first : null);
      _thumbNewIndex = null;
    }

    addressCtrl.addListener(() {
      final current = addressCtrl.text.trim();

      // ignore initial population
      if (_lastGeocodedAddress.isEmpty && widget.initial != null) {
        _lastGeocodedAddress = current;
      }

      final changed = current.isNotEmpty && current != _lastGeocodedAddress;

      if (changed && !_addressDirty) {
        setState(() {
          _addressDirty = true;
          serviceLat = null;
          serviceLng = null;
          serviceGeohash = null;
          _lastLatLng = null;
        });
      }

      if (!changed && _addressDirty) {
        setState(() => _addressDirty = false);
      }
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    discountCtrl.dispose();
    hoursCtrl.dispose();
    minsCtrl.dispose();
    descCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  double _parseDouble(String s) => double.tryParse(s.trim()) ?? 0;
  int _parseInt(String s) => int.tryParse(s.trim()) ?? 0;

  Future<void> _save() async {
    setState(() => saving = true);
    setState(() => errorText = null);

    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => errorText = "Service name is required.");
      return;
    }
    if (category == null) {
      setState(() => errorText = "Please select a category.");
      return;
    }

    final addr = addressCtrl.text.trim();
    if (addr.isEmpty) {
      setState(() => errorText = "Please enter an address.");
      return;
    }

    final price = _parseDouble(priceCtrl.text);
    if (price <= 0) {
      setState(() => errorText = "Price must be greater than 0.");
      return;
    }

    final discount = _parseDouble(discountCtrl.text).clamp(0.0, 100.0).toDouble();

    final h = _parseInt(hoursCtrl.text).clamp(0, 24);
    final m = _parseInt(minsCtrl.text).clamp(0, 59);

    final durationHr = h + (m / 60.0);
    if (durationHr <= 0) {
      setState(() => errorText = "Duration must be greater than 0.");
      return;
    }

    final packageAfterDiscount = price * (1.0 - discount / 100.0);
    final hourlyRate = packageAfterDiscount / durationHr;

    try {
      final ok = await _ensureLatLngFromAddress(addr);
      if (!ok) {
        setState(() => errorText = "Couldn't find location from address. Please pin the location.");
        setState(() => saving = false);
        return;
      }

      final isEdit = widget.initial != null;
      final serviceId = isEdit ? widget.initial!.id : repo.newServiceId();
      final existingKept = _existingPhotoUrls.where((u) => !_removedExistingUrls.contains(u)).toList();
      final uploaded = await repo.uploadServicePhotos(serviceId: serviceId, files: _newFiles);
      final finalPhotoUrls = <String>[...existingKept, ...uploaded];
      String? thumb = _thumbExistingUrl;

      if (_thumbNewIndex != null) {
        // new photos correspond in order to uploaded list
        if (_thumbNewIndex! >= 0 && _thumbNewIndex! < uploaded.length) {
          thumb = uploaded[_thumbNewIndex!];
        }
      }

      thumb ??= finalPhotoUrls.isNotEmpty ? finalPhotoUrls.first : null;

      final base = ProviderServiceUi(
        id: serviceId ?? "",
        providerId: widget.initial?.providerId ?? "",
        name: name,
        category: category!,
        address: addr,
        type: type,
        status: status,
        photoUrls: finalPhotoUrls,
        thumbnailUrl: thumb,
        price: price,
        discount: discount,
        pricingRules: _pricingRules,
        pricingCaps: _pricingCaps,
        hourlyRate: hourlyRate,
        durationHours: h,
        durationMins: m,
        description: descCtrl.text.trim(),
        featured: featured,
        ratingAvg: widget.initial?.ratingAvg ?? 0.0,
        ratingCount: widget.initial?.ratingCount ?? 0,
        lat: serviceLat,
        lng: serviceLng,
        geohash: serviceGeohash,
        createdAt: widget.initial?.createdAt,
        updatedAt: widget.initial?.updatedAt,
      );

      final saved = (widget.initial == null)
          ? await repo.createService(base)
          : await repo.updateService(base);

      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorText = "Save failed. Please try again.");
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
      if (pretty.isNotEmpty) {
        addressCtrl.text = pretty;
      }
    } catch (_) {}
  }

  Future<void> _pickServicePin() async {
    final init = _lastLatLng ?? const LatLng(3.1390, 101.6869);

    final result = await Navigator.push<MapPickResult>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerScreen(initial: init)),
    );

    if (result == null) return;

    setState(() {
      serviceLat = result.lat;
      serviceLng = result.lng;
      serviceGeohash = result.geohash;
      _lastLatLng = LatLng(result.lat, result.lng);
    });

    final formatted = (result.formattedAddress ?? '').trim();
    if (formatted.isNotEmpty) {
      addressCtrl.text = formatted;
      _lastGeocodedAddress = addressCtrl.text.trim();
      _addressDirty = false;
    } else {
      await _fillAddressFromPin(result.lat, result.lng);
      _lastGeocodedAddress = addressCtrl.text.trim();
      _addressDirty = false;
    }
  }

  Future<void> _useBusinessAddress() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final m = doc.data() ?? {};

    final addr = (m['businessAddress'] ?? '').toString();
    final lat = (m['businessLat'] as num?)?.toDouble();
    final lng = (m['businessLng'] as num?)?.toDouble();
    final gh  = (m['businessGeohash'] ?? '').toString();

    if (addr.trim().isEmpty || lat == null || lng == null || gh.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please set your Business Address first.")),
      );
      return;
    }

    setState(() {
      addressCtrl.text = addr;
      serviceLat = lat;
      serviceLng = lng;
      serviceGeohash = gh;
      _lastLatLng = LatLng(lat, lng);
      _lastGeocodedAddress = addr.trim();
      _addressDirty = false;
    });
  }

  Future<bool> _ensureLatLngFromAddress(String addr) async {
    // Only geocode if missing or address was edited since last geocode
    final needs = serviceLat == null || serviceLng == null || _addressDirty;

    if (!needs) return true;

    try {
      final locs = await geo.locationFromAddress(addr);
      if (locs.isEmpty) return false;

      final loc = locs.first;

      final placemarks = await geo.placemarkFromCoordinates(loc.latitude, loc.longitude);
      final p = placemarks.isNotEmpty ? placemarks.first : null;

      final resolved = [
        p?.name, p?.street, p?.subLocality, p?.locality, p?.postalCode, p?.administrativeArea, p?.country
      ].whereType<String>().join(" ").toLowerCase();

      final tokens = addr
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((t) => t.length >= 3)
          .toList();

      final hits = tokens.where((t) => resolved.contains(t)).length;

      if (tokens.isNotEmpty && hits < 2) return false;

      setState(() {
        serviceLat = loc.latitude;
        serviceLng = loc.longitude;
        serviceGeohash = GeoHash.encode(loc.latitude, loc.longitude, precision: 9);
        _lastLatLng = LatLng(loc.latitude, loc.longitude);
        _lastGeocodedAddress = addr.trim();
        _addressDirty = false;
      });

      return true;
    } catch (_) {
      return false;
    }
  }


  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            children: [
              _TopBar(
                title: isEdit ? "Edit Service" : "Add Service",
                onBack: () => Navigator.pop(context),
              ),
              const SizedBox(height: 14),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    if (errorText != null) ...[
                      _ErrorBanner(text: errorText!),
                      const SizedBox(height: 12),
                    ],

                    _buildPhotosPicker(),
                    const SizedBox(height: 14),

                    _Card(
                      child: Column(
                        children: [
                          _LabeledField(label: "Service Name", child: TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: "e.g., House Cleaning"))),
                          const SizedBox(height: 12),

                          _DropdownField<String>(
                            label: "Category",
                            value: category,
                            hint: "Select Category",
                            items: categories,
                            onChanged: (v) => setState(() => category = v),
                          ),
                          const SizedBox(height: 12),

                          _LabeledField(
                            label: "Address",
                            child: TextField(
                              controller: addressCtrl,
                              decoration: const InputDecoration(
                                hintText: "Street, area, postcode, city",
                              ),
                              maxLines: 2,
                            ),
                          ),

                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton.tonal(
                                    onPressed: _useBusinessAddress,
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text("Use Business Address"),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton.tonal(
                                    onPressed: _pickServicePin,
                                    child: Text(serviceLat == null ? "Pick Location Pin" : "Change Pin"),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          Text(
                            (serviceLat != null && serviceLng != null)
                                ? "Pinned • ${serviceLat!.toStringAsFixed(5)}, ${serviceLng!.toStringAsFixed(5)}"
                                : "No pin yet",
                            style: const TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
                          ),

                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: _DropdownField<ServiceType>(
                                  label: "Type",
                                  value: type,
                                  hint: "Type",
                                  items: ServiceType.values,
                                  itemLabel: (v) => v == ServiceType.onsite ? "On-site" : "Remote",
                                  onChanged: (v) => setState(() => type = v ?? ServiceType.onsite),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _DropdownField<ServiceStatus>(
                                  label: "Status",
                                  value: status,
                                  hint: "Status",
                                  items: ServiceStatus.values,
                                  itemLabel: (v) => v == ServiceStatus.active ? "Active" : "Inactive",
                                  onChanged: (v) => setState(() => status = v ?? ServiceStatus.active),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: _LabeledField(
                                  label: "Package Price (RM)",
                                  child: TextField(
                                    controller: priceCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(hintText: "e.g., 80"),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LabeledField(
                                  label: "Discount (%)",
                                  child: TextField(
                                    controller: discountCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(hintText: "e.g., 10"),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: _LabeledField(
                                  label: "Duration Hours",
                                  child: TextField(
                                    controller: hoursCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(hintText: "e.g., 1"),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LabeledField(
                                  label: "Duration Mins",
                                  child: TextField(
                                    controller: minsCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(hintText: "e.g., 30"),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          _LabeledField(
                            label: "Description",
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white, // or your KLPalette.bg / mutedBg
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: KLPalette.border),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: TextField(
                                  controller: descCtrl,
                                  maxLines: 5,
                                  decoration: const InputDecoration(
                                    hintText: "Description of service",
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Checkbox(
                                value: featured,
                                onChanged: (v) => setState(() => featured = v ?? false),
                              ),
                              const Text(
                                "Set as Featured",
                                style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text2),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _DynamicPricingTile(
                            rulesCount: _pricingRules.length,
                            caps: _pricingCaps,
                            onTap: () async {
                              final result = await Navigator.push<PricingEditorResult>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DynamicPricingRulesEditorScreen(
                                    initialRules: _pricingRules,
                                    initialCaps: _pricingCaps,
                                  ),
                                ),
                              );

                              if (result != null) {
                                setState(() {
                                  _pricingRules = result.rules;
                                  _pricingCaps = result.caps;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: KLPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : Text(isEdit ? "Save Changes" : "Save", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotosPicker() {
    final total = (_existingPhotoUrls.where((u) => !_removedExistingUrls.contains(u)).length) + _newFiles.length;

    Future<void> addPhotos() async {
      final picked = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1600);
      if (picked.isEmpty) return;

      // read bytes once for preview
      for (final f in picked) {
        final b = await f.readAsBytes();
        _newFiles.add(f);
        _newBytes.add(b);
      }

      // auto set thumbnail if none yet
      if (_thumbExistingUrl == null && _thumbNewIndex == null) {
        if (_existingPhotoUrls.where((u) => !_removedExistingUrls.contains(u)).isNotEmpty) {
          _thumbExistingUrl = _existingPhotoUrls.firstWhere((u) => !_removedExistingUrls.contains(u));
        } else {
          _thumbNewIndex = 0;
        }
      }

      if (mounted) setState(() {});
    }

    void setThumbExisting(String url) {
      setState(() {
        _thumbExistingUrl = url;
        _thumbNewIndex = null;
      });
    }

    void setThumbNew(int idx) {
      setState(() {
        _thumbNewIndex = idx;
        _thumbExistingUrl = null;
      });
    }

    void removeExisting(String url) {
      setState(() {
        _removedExistingUrls.add(url);

        // if removed thumbnail, reset thumbnail
        if (_thumbExistingUrl == url) {
          _thumbExistingUrl = null;
          _thumbNewIndex = null;

          final remainExisting = _existingPhotoUrls.where((u) => !_removedExistingUrls.contains(u)).toList();
          if (remainExisting.isNotEmpty) {
            _thumbExistingUrl = remainExisting.first;
          } else if (_newFiles.isNotEmpty) {
            _thumbNewIndex = 0;
          }
        }
      });
    }

    void removeNew(int idx) {
      setState(() {
        _newFiles.removeAt(idx);
        _newBytes.removeAt(idx);

        // adjust thumbnail new index if needed
        if (_thumbNewIndex != null) {
          if (_thumbNewIndex == idx) {
            _thumbNewIndex = null;
            _thumbExistingUrl = null;

            final remainExisting = _existingPhotoUrls.where((u) => !_removedExistingUrls.contains(u)).toList();
            if (remainExisting.isNotEmpty) {
              _thumbExistingUrl = remainExisting.first;
            } else if (_newFiles.isNotEmpty) {
              _thumbNewIndex = 0;
            }
          } else if (_thumbNewIndex! > idx) {
            _thumbNewIndex = _thumbNewIndex! - 1;
          }
        }
      });
    }

    final existing = _existingPhotoUrls.where((u) => !_removedExistingUrls.contains(u)).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: KLPalette.border, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text("Photos", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(width: 8),
                Text("$total", style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text2)),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: addPhotos,
                  child: const Text("Add"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (total == 0)
              InkWell(
                onTap: addPhotos,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: KLPalette.mutedBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: KLPalette.border),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined, size: 42, color: KLPalette.text2),
                        SizedBox(height: 10),
                        Text("Add photos", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        SizedBox(height: 6),
                        Text("Pick multiple • Tap star for thumbnail", style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  // existing URLs
                  for (final url in existing)
                    _photoTile(
                      isThumb: _thumbExistingUrl == url,
                      child: Image.network(url, fit: BoxFit.cover),
                      onSetThumb: () => setThumbExisting(url),
                      onRemove: () => removeExisting(url),
                    ),

                  // new local picks
                  for (int i = 0; i < _newBytes.length; i++)
                    _photoTile(
                      isThumb: _thumbNewIndex == i,
                      child: Image.memory(_newBytes[i], fit: BoxFit.cover),
                      onSetThumb: () => setThumbNew(i),
                      onRemove: () => removeNew(i),
                    ),

                  // add tile
                  InkWell(
                    onTap: addPhotos,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: KLPalette.mutedBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: const Center(child: Icon(Icons.add, color: KLPalette.text2, size: 30)),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 8),
            const Text(
              "Tip: Tap a photo’s ★ to set thumbnail (used for hero image).",
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoTile({
    required Widget child,
    required bool isThumb,
    required VoidCallback onSetThumb,
    required VoidCallback onRemove,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: isThumb ? KLPalette.primary : KLPalette.border, width: isThumb ? 3 : 1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: child,
            ),
          ),

          // set thumbnail
          Positioned(
            right: 6,
            top: 6,
            child: InkWell(
              onTap: onSetThumb,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isThumb ? Icons.star_rounded : Icons.star_border_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),

          // remove
          Positioned(
            left: 6,
            top: 6,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
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
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePickerBox extends StatelessWidget {
  final VoidCallback onTap;
  const _ImagePickerBox({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: KLPalette.border, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.image_outlined, size: 42, color: KLPalette.text2),
              SizedBox(height: 10),
              Text("Choose Image", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              SizedBox(height: 10),
              Text("Support: JPG, PNG, JPEG", style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: KLPalette.mutedBg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: KLPalette.border),
        ),
        child: child,
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final String hint;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T v)? itemLabel;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledField(
      label: label,
      child: DropdownButtonFormField<T>(
        value: value,
        items: items
            .map((v) => DropdownMenuItem<T>(
          value: v,
          child: Text(itemLabel?.call(v) ?? v.toString()),
        ))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          suffixIcon: const Icon(Icons.expand_more_rounded),
        ),
        icon: const SizedBox.shrink(),
      ),
    );
  }
}

class _DynamicPricingTile extends StatelessWidget {
  final int rulesCount;
  final Map<String, dynamic>? caps;
  final VoidCallback onTap;

  const _DynamicPricingTile({
    required this.rulesCount,
    required this.caps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final capsText = (caps == null || caps!.isEmpty) ? "No caps" : "Caps set";
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: KLPalette.mutedBg,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: const Icon(Icons.tune_rounded, color: KLPalette.text),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Dynamic Pricing (optional)", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    "$rulesCount rules • $capsText",
                    style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: KLPalette.text2),
          ],
        ),
      ),
    );
  }
}