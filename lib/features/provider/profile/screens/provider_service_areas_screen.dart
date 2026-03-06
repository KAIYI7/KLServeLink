import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/core/utils/app_snack.dart';
import '../../../../core/theme/theme.dart';

class ProviderServiceAreasScreen extends StatefulWidget {
  const ProviderServiceAreasScreen({super.key});

  @override
  State<ProviderServiceAreasScreen> createState() => _ProviderServiceAreasScreenState();
}

class _ProviderServiceAreasScreenState extends State<ProviderServiceAreasScreen> {
  final inputCtrl = TextEditingController();

  bool loading = true;
  bool saving = false;
  bool dirty = false;

  // Display-only areas (chips)
  List<String> areas = [];

  // Coverage (useful for eligibility checks later)
  double radiusKm = 10;

  // Center
  double? centerLat;
  double? centerLng;
  String centerLabel = "";

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? <String, dynamic>{};

    // serviceAreas
    final rawAreas = data['serviceAreas'];
    areas = (rawAreas is List)
        ? rawAreas.map((e) => e.toString()).map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    // serviceCoverage.radiusKm
    final sc = data['serviceCoverage'];
    if (sc is Map) {
      final mm = sc.cast<String, dynamic>();
      final r = mm['radiusKm'];
      if (r is num) radiusKm = r.toDouble().clamp(1, 50);

      // Center
      final c = mm['center'];
      if (c is Map) {
        final cc = c.cast<String, dynamic>();
        final lt = cc['lat'];
        final lg = cc['lng'];
        if (lt is num) centerLat = lt.toDouble();
        if (lg is num) centerLng = lg.toDouble();
        centerLabel = (cc['label'] ?? cc['text'] ?? '').toString().trim();
      }
    }

    // If no coverage center stored, try to auto-use businessAddress coords (if present)
    if (centerLat == null || centerLng == null) {
      final lt = data['businessLat'];
      final lg = data['businessLng'];

      if (lt is num) centerLat = lt.toDouble();
      if (lg is num) centerLng = lg.toDouble();

      centerLabel = (data['businessAddress'] ?? '')
          .toString()
          .trim();
    }

    if (mounted) {
      setState(() {
        loading = false;
        dirty = false;
      });
    }
  }

  void _setDirty() {
    if (!dirty) setState(() => dirty = true);
  }

  void _addArea() {
    final v = inputCtrl.text.trim();
    if (v.isEmpty) return;

    final exists = areas.any((a) => a.toLowerCase() == v.toLowerCase());
    if (exists) {
      AppSnack.show(context, "Area already added", type: AppSnackType.error);
      return;
    }

    setState(() {
      areas.add(v);
      inputCtrl.clear();
      dirty = true;
    });
  }

  void _removeArea(String a) {
    setState(() {
      areas.remove(a);
      dirty = true;
    });
  }

  void _clearAreas() {
    if (areas.isEmpty) return;
    setState(() {
      areas.clear();
      dirty = true;
    });
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => saving = true);
    try {
      final payload = <String, dynamic>{
        'serviceAreas': areas,
        'serviceCoverage': {
          'radiusKm': radiusKm,
          // store center only if we have it
          if (centerLat != null && centerLng != null)
            'center': {
              'lat': centerLat,
              'lng': centerLng,
              if (centerLabel.trim().isNotEmpty) 'label': centerLabel.trim(),
            },
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        payload,
        SetOptions(merge: true),
      );

      if (!mounted) return;
      AppSnack.show(context, "Coverage & areas saved", type: AppSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(context, "Save failed: $e", type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!dirty) return true;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Discard changes?"),
          content: const Text(
            "You have unsaved changes. Leave without saving?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Stay"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Discard"),
            ),
          ],
        );
      },
    );

    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !dirty,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (ok && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: KLPalette.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              children: [
                _TopBar(
                  title: "Service Coverage",
                  onBack: () async {
                    final ok = await _confirmDiscard();
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                  onClear: areas.isEmpty ? null : _clearAreas,
                ),
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
                          : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ===== Coverage section =====
                          const Text(
                            "Coverage radius",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Used to decide whether a booking is within your service distance.",
                            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),

                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [5, 10, 20, 30].map((v) {
                              final selected = radiusKm.round() == v;
                              return InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () {
                                  setState(() {
                                    radiusKm = v.toDouble();
                                    dirty = true;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected ? KLPalette.primary : KLPalette.tint50,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: KLPalette.border),
                                  ),
                                  child: Text(
                                    "$v km",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: selected ? Colors.white : KLPalette.primary700,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: radiusKm.clamp(1, 50),
                                  min: 1,
                                  max: 50,
                                  divisions: 49,
                                  onChanged: (v) {
                                    setState(() => radiusKm = v);
                                    _setDirty();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: KLPalette.tint50,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: KLPalette.border),
                                ),
                                child: Text(
                                  "${radiusKm.toStringAsFixed(0)} km",
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                          _InlineInfo(
                            icon: Icons.place_outlined,
                            text: (centerLat != null && centerLng != null)
                                ? "Coverage center: ${centerLabel.isNotEmpty ? centerLabel : "business location"}"
                                : "Coverage center not set (will still save radius). Add business address coordinates for best results.",
                          ),

                          const SizedBox(height: 16),
                          const Divider(height: 1, color: KLPalette.border),
                          const SizedBox(height: 14),

                          // ===== Areas section =====
                          Row(
                            children: [
                              const Text(
                                "Service areas",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                              const Spacer(),
                              Text(
                                "${areas.length}",
                                style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Shown on your provider profile (e.g. Cheras, Bangsar).",
                            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: inputCtrl,
                                  decoration: const InputDecoration(
                                    hintText: "Type area name",
                                    prefixIcon: Icon(Icons.map_outlined),
                                  ),
                                  onSubmitted: (_) => _addArea(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: _addArea,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(56, 56),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Icon(Icons.add),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Chips list (scrollable)
                          Expanded(
                            child: areas.isEmpty
                                ? Center(
                              child: Text(
                                "No areas added yet.",
                                style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                              ),
                            )
                                : SingleChildScrollView(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: areas.map((a) {
                                  return Chip(
                                    label: Text(a, style: const TextStyle(fontWeight: FontWeight.w900)),
                                    deleteIcon: const Icon(Icons.close),
                                    onDeleted: () => _removeArea(a),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: saving ? null : _save,
                              child: saving
                                  ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                                  : const Text(
                                "Save",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InlineInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KLPalette.tint50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KLPalette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: KLPalette.text2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.3),
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
  final VoidCallback? onClear;

  const _TopBar({
    required this.title,
    required this.onBack,
    this.onClear,
  });

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
        const SizedBox(width: 48,),
      ],
    );
  }
}