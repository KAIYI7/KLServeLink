import 'package:flutter/material.dart';
import 'package:fyp_flutter/features/seeker/services/screens/service_details_screen.dart';
import '../../../../core/models/service_category.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/ui_components.dart';
import '../../navigation/seeker_nav_controller.dart';
import 'dart:math' as _m;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../data/seeker_services_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../profile/data/seeker_user_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../addresses/data/seeker_address_firestore.dart';

class SearchScreen extends StatefulWidget {
  final SeekerNavController nav;

  const SearchScreen({
    super.key,
    required this.nav,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ctrl = TextEditingController();

  bool hasSearched = false;
  bool showMap = false;

  final repo = SeekerServicesRepo();

  final _userFs = SeekerUserFirestore();
  final _historyRepo = SeekerSearchHistoryRepo();
  final _addrFs = SeekerAddressFirestore();

  LatLng? _myLocation;
  bool _locLoading = false;
  String? _locError;

  SearchFilters filters = const SearchFilters();
  final userCenter = const LatLng(3.1390, 101.6869); // demo center

  @override
  void initState() {
    super.initState();
    widget.nav.searchIntent.addListener(_onSearchIntent);
    _initMyLocation();
  }

  Future<void> _initMyLocation() async {
    setState(() {
      _locLoading = true;
      _locError = null;
    });

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() {
          _locError = "Location services are disabled.";
          _locLoading = false;
        });
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() {
          _locError = "Location permission not granted.";
          _locLoading = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _myLocation = LatLng(pos.latitude, pos.longitude);
        _locLoading = false;
      });
    } catch (e) {
      setState(() {
        _locError = "Failed to get location.";
        _locLoading = false;
      });
    }
  }

  Stream<LatLng?> _streamMainCenter() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);

    return _addrFs.streamMainAddress(uid: uid).map((a) {
      if (a == null) return null;

      final lat = a.lat;
      final lng = a.lng;

      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    });
  }

  void _onSearchIntent() {
    final intent = widget.nav.searchIntent.value;
    if (intent == null) return;

    if (intent.category != null) {
      final key = intent.category!.key;

      // Save category label as a recent search (e.g., "Cleaning")
      final label = _labelForCategoryKey(key);
      if (label != null) {
        _historyRepo.bump(label);
      }

      setState(() {
        filters = filters.copyWith(categoryKey: key);
        ctrl.clear();
        hasSearched = true;
        showMap = false;
      });
    } else if (intent.query != null) {
      final q = intent.query!.trim();
      if (q.isNotEmpty) {
        _historyRepo.bump(q);
      }

      setState(() {
        filters = filters.copyWith(clearCategory: true);
        ctrl.text = intent.query!;
        hasSearched = true;
        showMap = false;
      });
    }

    widget.nav.searchIntent.value = null;
  }

  @override
  void dispose() {
    widget.nav.searchIntent.removeListener(_onSearchIntent);
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ctrl.text.trim();

    final showResults = query.isNotEmpty || filters.hasActiveFilters || hasSearched;

    return StreamBuilder<LatLng?>(
      stream: _streamMainCenter(),
      builder: (context, centerSnap) {
        final mainCenter = centerSnap.data;

        // Priority: main address -> GPS -> demo
        final effectiveCenter = mainCenter ?? _myLocation ?? userCenter;

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                children: [
                  _TopSearchBar(
                    controller: ctrl,
                    onBack: () {
                      final q = ctrl.text.trim();
                      final hasActiveSearch = q.isNotEmpty ||
                          filters.categoryKey != null ||
                          filters.nearbyOnly ||
                          hasSearched ||
                          showMap;
        
                      if (hasActiveSearch) {
                        setState(() {
                          ctrl.clear();
                          filters = const SearchFilters();
                          hasSearched = false;
                          showMap = false;
                        });
                      } else {
                        widget.nav.tabIndex.value = 0;
                      }
                    },
                    onFilter: () async {
                      final updated = await showModalBottomSheet<SearchFilters>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: KLPalette.bg,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                        ),
                        builder: (_) => _SearchFilterSheet(initial: filters),
                      );
        
                      if (updated != null) {
                        if (updated.resetAll) {
                          setState(() {
                            ctrl.clear();
                            filters = const SearchFilters();
                            hasSearched = false;
                            showMap = false;
                          });
                          return;
                        }
        
                        setState(() {
                          filters = updated;
        
                          final q = ctrl.text.trim();
                          if (q.isEmpty && filters.hasActiveFilters) {
                            hasSearched = false;
                            showMap = false;
                          } else {
                            hasSearched = true;
                            showMap = false;
                          }
                        });
                      }
                    },
                    onChanged: (v) => setState(() {
                      final q = v.trim();
                      if (q.isEmpty && !filters.hasActiveFilters) {
                        hasSearched = false;
                        showMap = false;
                      }
                    }),
                    onSubmitted: (v) {
                      final q = v.trim();
                      if (q.isNotEmpty) _historyRepo.bump(q);
        
                      setState(() {
                        hasSearched = true;
                        showMap = false;
                      });
                    },
                    onClear: () => setState(() {
                      ctrl.clear();
                      filters = filters.copyWith(clearCategory: true);
                      hasSearched = false;
                      showMap = false;
                    }),
                  ),
                  const SizedBox(height: 14),
        
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: showResults
                          ? _SearchResults(
                        nav: widget.nav,
                        query: query,
                        showMap: showMap,
                        onToggleMap: () => setState(() => showMap = !showMap),
                        filters: filters,
                        center: effectiveCenter,
                        myLocation: _myLocation,
                        repo: repo,
                        onSearchAnother: () => setState(() {
                          ctrl.clear();
                          filters = const SearchFilters();
                          hasSearched = false;
                          showMap = false;
                        }),
                      )
                          : _SearchEmptyState(
                            nav: widget.nav,
                            userFs: _userFs,
                            svcRepo: repo,
                            historyRepo: _historyRepo,
                            onTapRecent: (s) {
                              _historyRepo.bump(s); // bump to top
                              setState(() {
                                ctrl.text = s;
                                hasSearched = true;
                                showMap = false;
                              });
                            },
                          ),
        
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  String? _labelForCategoryKey(String key) {
    for (final c in kCategories) {
      if (c.id.key == key) return c.label;
    }
    return null;
  }

}

/* ---------------- FILTER SHEET ---------------- */

class _SearchFilterSheet extends StatefulWidget {
  final SearchFilters initial;
  const _SearchFilterSheet({required this.initial});

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late String? _categoryKey;

  late bool nearbyOnly;
  late double radiusKm;

  late RangeValues priceRange;
  int? minRating;

  late final TextEditingController lowPriceCtrl;
  late final TextEditingController highPriceCtrl;

  @override
  void initState() {
    super.initState();
    nearbyOnly = widget.initial.nearbyOnly;
    radiusKm = widget.initial.radiusKm;
    _categoryKey = widget.initial.categoryKey;
    final minP = widget.initial.minPrice ?? 10;
    final maxP = widget.initial.maxPrice ?? 100;
    priceRange = RangeValues(minP.toDouble(), maxP.toDouble());
    lowPriceCtrl = TextEditingController(text: priceRange.start.toInt().toString());
    highPriceCtrl = TextEditingController(text: priceRange.end.toInt().toString());
    minRating = widget.initial.minRating;
  }

  @override
  void dispose() {
    lowPriceCtrl.dispose();
    highPriceCtrl.dispose();
    super.dispose();
  }

  void _syncPriceCtrls() {
    final a = priceRange.start.toInt().toString();
    final b = priceRange.end.toInt().toString();
    if (lowPriceCtrl.text != a) lowPriceCtrl.text = a;
    if (highPriceCtrl.text != b) highPriceCtrl.text = b;
  }

  void _setLowFromText(String v) {
    final n = int.tryParse(v);
    if (n == null) return;

    final end = priceRange.end.toInt();
    final startClamped = n.clamp(0, end).toDouble();

    setState(() {
      priceRange = RangeValues(startClamped, priceRange.end);
      _syncPriceCtrls();
    });
  }

  void _setHighFromText(String v) {
    final n = int.tryParse(v);
    if (n == null) return;

    final start = priceRange.start.toInt();
    final endClamped = n.clamp(start, 200).toDouble();

    setState(() {
      priceRange = RangeValues(priceRange.start, endClamped);
      _syncPriceCtrls();
    });
  }

  String _shortLabelForCategory(CategoryMeta c) {
    switch (c.id) {
      case ServiceCategory.aircon:
        return "Air-Con";
      case ServiceCategory.handyman:
        return "Repair";
      case ServiceCategory.tutoring:
        return "Tutoring";
      default:
        return c.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottomInset),
      child: SingleChildScrollView(
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
                const Text("Filters", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, const SearchFilters(resetAll: true));
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: KLPalette.primary,
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  child: const Text("Clear"),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),

            const SizedBox(height: 10),

            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KLPalette.bg,
                  border: Border.all(color: KLPalette.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.near_me, color: nearbyOnly ? KLPalette.primary : KLPalette.text2),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text("Nearby only", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    Switch(
                      value: nearbyOnly,
                      activeColor: KLPalette.primary,
                      onChanged: (v) => setState(() => nearbyOnly = v),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KLPalette.bg,
                  border: Border.all(color: KLPalette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Search radius", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text("${radiusKm.toStringAsFixed(0)} km",
                        style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800)),
                    Slider(
                      value: radiusKm,
                      min: 1,
                      max: 30,
                      divisions: 29,
                      activeColor: KLPalette.primary,
                      onChanged: nearbyOnly ? (v) => setState(() => radiusKm = v) : null,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KLPalette.bg,
                  border: Border.all(color: KLPalette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Category", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 96,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _CategoryCircleChoice(
                              label: "All",
                              icon: Icons.grid_view_rounded,
                              selected: _categoryKey == null,
                              onTap: () => setState(() => _categoryKey = null),
                            ),
                            ...kCategories.map((c) {
                              final key = c.id.key;
                              return _CategoryCircleChoice(
                                label: _shortLabelForCategory(c),
                                icon: c.icon,
                                selected: _categoryKey == key,
                                onTap: () => setState(() => _categoryKey = key),
                              );
                            }).expand((w) => [const SizedBox(width: 12), w]).skip(1),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KLPalette.bg,
                  border: Border.all(color: KLPalette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Price Range", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 10),
                    RangeSlider(
                      values: priceRange,
                      min: 0,
                      max: 200,
                      divisions: 40,
                      activeColor: KLPalette.primary,
                      onChanged: (v) => setState(() {
                        priceRange = v;
                        _syncPriceCtrls();
                      }),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: KLPalette.border),
                              color: KLPalette.bg,
                            ),
                            child: TextField(
                              controller: lowPriceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                hintText: "Low price",
                              ),
                              onChanged: _setLowFromText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: KLPalette.border),
                              color: KLPalette.bg,
                            ),
                            child: TextField(
                              controller: highPriceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                hintText: "High price",
                              ),
                              onChanged: _setHighFromText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KLPalette.bg,
                  border: Border.all(color: KLPalette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Rating", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _StarPillChoice(
                              label: "All",
                              selected: minRating == null,
                              onTap: () => setState(() => minRating = null),
                            ),
                            for (final r in [5, 4, 3, 2, 1]) ...[
                              const SizedBox(width: 10),
                              _StarPillChoice(
                                label: "$r",
                                selected: minRating == r,
                                onTap: () => setState(() => minRating = r),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE5E7EB),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: () {
                        setState(() {
                          nearbyOnly = false;
                          radiusKm = 5;
                          _categoryKey = null;
                          priceRange = const RangeValues(10, 100);
                          minRating = null;
                          _syncPriceCtrls();
                        });
                      },
                      child: const Text("Reset", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: KLPalette.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: () {
                        Navigator.pop(
                          context,
                          SearchFilters(
                            nearbyOnly: nearbyOnly,
                            radiusKm: radiusKm,
                            categoryKey: _categoryKey,
                            minPrice: priceRange.start.toInt(),
                            maxPrice: priceRange.end.toInt(),
                            minRating: minRating,
                          ),
                        );
                      },
                      child: const Text("Apply", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- TOP BAR / EMPTY STATE ---------------- */

class _TopSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onBack;
  final VoidCallback onFilter;
  final VoidCallback onClear;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  const _TopSearchBar({
    required this.controller,
    required this.onBack,
    required this.onFilter,
    required this.onClear,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleIconButton(
          icon: Icons.arrow_back,
          onTap: onBack,
          filled: false,
          size: 52,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            onSubmitted: (value) {
              FocusScope.of(context).unfocus();
              onSubmitted?.call(value);
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: "Search a service",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        CircleIconButton(
          icon: Icons.tune_rounded,
          filled: true,
          onTap: onFilter,
          size: 52,
        ),
      ],
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  final SeekerNavController nav;
  final SeekerUserFirestore userFs;
  final SeekerServicesRepo svcRepo;
  final SeekerSearchHistoryRepo historyRepo;
  final ValueChanged<String> onTapRecent;

  const _SearchEmptyState({
    required this.nav,
    required this.userFs,
    required this.svcRepo,
    required this.historyRepo,
    required this.onTapRecent,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text("Recommended for You", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),

        // Recommended for You
        StreamBuilder<List<String>>(
          stream: userFs.streamMyRecommendations(limit: 5),
          builder: (context, recSnap) {
            if (!recSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final ids = recSnap.data ?? const <String>[];

            // Fallback to popular if no recommendations yet
            if (ids.isEmpty) {
              return StreamBuilder<List<SeekerServiceUi>>(
                stream: svcRepo.streamPopular(limit: 3),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final list = snap.data ?? const <SeekerServiceUi>[];
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        "No recommendations yet.",
                        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      for (int i = 0; i < list.length; i++) ...[
                        _RecommendedStripCardFromFs(
                          nav: nav,
                          service: list[i],
                          tint: (i == 0)
                              ? const Color(0xFF0EA5E9)
                              : (i == 1)
                              ? KLPalette.primary
                              : const Color(0xFF60A5FA),
                        ),
                        if (i != list.length - 1) const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              );
            }

            // Personalized recommendations
            return StreamBuilder<List<SeekerServiceUi>>(
              stream: svcRepo.streamByIds(ids),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final list = snap.data ?? const <SeekerServiceUi>[];
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      "No recommended services found.",
                      style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                    ),
                  );
                }

                final top3 = list.take(3).toList();
                return Column(
                  children: [
                    for (int i = 0; i < top3.length; i++) ...[
                      _RecommendedStripCardFromFs(
                        nav: nav,
                        service: top3[i],
                        tint: (i == 0)
                            ? const Color(0xFF0EA5E9)
                            : (i == 1)
                            ? KLPalette.primary
                            : const Color(0xFF60A5FA),
                      ),
                      if (i != top3.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            );
          },
        ),

        const SizedBox(height: 18),

        // Recent searches
        StreamBuilder<List<String>>(
          stream: historyRepo.streamMyHistory(limit: 8),
          builder: (context, snap) {
            final items = snap.data ?? const <String>[];

            return Column(
              children: [
                Row(
                  children: [
                    Text("Recent", style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (items.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => historyRepo.clear(),
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                        label: const Text(
                          "Clear All",
                          style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      "No recent searches yet.",
                      style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                    ),
                  )
                else
                  ...items.map(
                        (s) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, color: KLPalette.text2),
                      title: Text(s, style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: KLPalette.text2),
                        onPressed: () => historyRepo.remove(s),
                      ),
                      onTap: () => onTapRecent(s),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecommendedStripCardFromFs extends StatelessWidget {
  final SeekerNavController nav;
  final SeekerServiceUi service;
  final Color tint;

  const _RecommendedStripCardFromFs({
    required this.nav,
    required this.service,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final s = service;
    final finalPrice = (s.price.toDouble() * (1.0 - s.discount.toDouble().clamp(0.0, 100.0) / 100.0))
        .clamp(0.0, 1e12);
    final priceText = finalPrice > 0 ? "RM ${finalPrice.toStringAsFixed(0)}" : "RM -";
    final ratingText = s.rating > 0 ? s.rating.toStringAsFixed(1) : "-";

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDetailsScreen.fromServiceId(
              nav: nav,
              serviceId: s.id,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: KLPalette.border),
            color: tint.withOpacity(0.14),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(opacity: 0.10, child: Container(color: tint)),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text(priceText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                        const SizedBox(width: 6),
                        Text(ratingText, style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 56,
                      width: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: KLPalette.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _SeekerServiceCoverImage(service: s),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- RESULTS ---------------- */

class _SearchResults extends StatelessWidget {
  final SeekerNavController nav;
  final String query;
  final bool showMap;
  final VoidCallback onToggleMap;
  final SearchFilters filters;
  final LatLng center;
  final LatLng? myLocation;
  final SeekerServicesRepo repo;
  final VoidCallback onSearchAnother;

  const _SearchResults({
    required this.nav,
    required this.query,
    required this.showMap,
    required this.onToggleMap,
    required this.filters,
    required this.center,
    required this.myLocation,
    required this.repo,
    required this.onSearchAnother,
  });

  bool _matchCategory(SeekerServiceUi s, String categoryKey) {
    final a = s.category.trim().toLowerCase();
    final b = categoryKey.trim().toLowerCase();
    if (a == b) return true;
    // common fallback: "cleaning" matches "cleaning service", "cleaning", etc.
    return a.contains(b);
  }

  @override
  Widget build(BuildContext context) {
    final heading = query.isNotEmpty
        ? 'Result for “$query”'
        : (filters.categoryKey != null ? 'Result for “${filters.categoryKey}”' : 'Results');

    return StreamBuilder<List<SeekerServiceUi>>(
      stream: repo.watchActive(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snap.data ?? [];

        final filtered = all.where((s) {
          final finalPrice = (s.price.toDouble() *
              (1.0 - s.discount.toDouble().clamp(0.0, 100.0) / 100.0))
              .clamp(0.0, 1e12);

          // text query
          if (query.isNotEmpty) {
            final hay = "${s.name} ${s.category} ${s.address}".toLowerCase();
            if (!hay.contains(query.toLowerCase())) return false;
          }

          // category
          if (filters.categoryKey != null) {
            if (!_matchCategory(s, filters.categoryKey!)) return false;
          }

          // price
          if (filters.minPrice != null && finalPrice < filters.minPrice!) return false;
          if (filters.maxPrice != null && finalPrice > filters.maxPrice!) return false;

          // rating
          if (filters.minRating != null && s.rating < filters.minRating!.toDouble()) return false;

          // nearby
          if (filters.nearbyOnly) {
            if (s.lat == null || s.lng == null) return false;
            final d = haversineKm(center.latitude, center.longitude, s.lat!, s.lng!);
            if (d > filters.radiusKm) return false;
          }

          return true;
        }).toList();

        if (filtered.isEmpty) {
          return _SearchNotFoundState(
            query: query.isEmpty ? (filters.categoryKey ?? "") : query,
            onSearchAnother: onSearchAnother,
          );
        }

        return Stack(
          children: [
            ListView(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(heading, style: Theme.of(context).textTheme.titleLarge)),
                    if (filters.nearbyOnly)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: KLPalette.tint50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: KLPalette.border),
                        ),
                        child: Text(
                          "≤ ${filters.radiusKm.toStringAsFixed(0)} km",
                          style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Text("${filtered.length} Found", style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 14),

                if (showMap) ...[
                  _MapPreviewFirestore(
                    onClose: onToggleMap,
                    center: center,
                    myLocation: myLocation,
                    results: filtered,
                    onOpenFullMap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullSearchMapScreen(
                            center: center,
                            myLocation: myLocation,
                            results: filtered,
                            nav: nav,
                          ),
                        ),
                      );
                    },
                    onOpenService: (serviceId) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceDetailsScreen.fromServiceId(
                            nav: nav,
                            serviceId: serviceId,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                ],

                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.72,
                  ),
                  itemBuilder: (context, i) {
                    final s = filtered[i];
                    final finalPrice = (s.price.toDouble() *
                        (1.0 - s.discount.toDouble().clamp(0.0, 100.0) / 100.0))
                        .clamp(0.0, 1e12);

                    return _ResultCard(
                      nav: nav,
                      service: s,
                      saved: i.isEven,
                    );
                  },
                ),

                const SizedBox(height: 90),
              ],
            ),

            if (!showMap)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 55),
                  child: _DarkPillButton(
                    label: "Show Map",
                    icon: Icons.public,
                    onTap: onToggleMap,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SearchNotFoundState extends StatelessWidget {
  final String query;
  final VoidCallback onSearchAnother;

  const _SearchNotFoundState({
    required this.query,
    required this.onSearchAnother,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Result for “$query”', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 30),
        Center(
          child: Container(
            height: 220,
            width: 260,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KLPalette.tint50,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: KLPalette.border),
            ),
            child: const Icon(Icons.markunread_mailbox_rounded, size: 120, color: KLPalette.text2),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text("Service Not Found", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28)),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 26),
            child: Text(
              "Sorry, the keyword you entered cannot be found,\nplease check again or search with another keyword",
              textAlign: TextAlign.center,
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KLPalette.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            onPressed: onSearchAnother,
            child: const Text("Search another", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

class _MapPreviewFirestore extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onOpenFullMap;
  final LatLng center;
  final LatLng? myLocation;
  final List<SeekerServiceUi> results;
  final ValueChanged<String> onOpenService;

  const _MapPreviewFirestore({
    required this.onClose,
    required this.center,
    required this.myLocation,
    required this.results,
    required this.onOpenFullMap,
    required this.onOpenService,
  });

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      // Main address marker (green)
      Marker(
        markerId: const MarkerId("main_address"),
        position: center,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: "Main Address"),
      ),

      // My location marker (blue)
      if (myLocation != null)
        Marker(
          markerId: const MarkerId("me"),
          position: myLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: "You"),
        ),

      // Service markers (red)
      ...results
          .where((s) => s.lat != null && s.lng != null)
          .map(
            (s) {
          final finalPrice = (s.price.toDouble() *
              (1.0 - s.discount.toDouble().clamp(0.0, 100.0) / 100.0))
              .clamp(0.0, 1e12);

          return Marker(
            markerId: MarkerId(s.id),
            position: LatLng(s.lat!, s.lng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: s.name,
              snippet: "RM ${finalPrice.toStringAsFixed(0)} • Tap to view",
              onTap: () => onOpenService(s.id),
            ),
            onTap: () {},
          );
        },
      ),
    };

    final camTarget = center;

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: camTarget, zoom: 13),
              myLocationEnabled: true,     // blue dot (if permission granted)
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              markers: markers,
              compassEnabled: true,
            ),

            Positioned(
              left: 5,
              bottom: 5,
              child: _MapLegend(
                showMePin: myLocation != null,
                showGpsDot: true,
              ),
            ),

            Positioned(
              right: 14,
              top: 14,
              child: Row(
                children: [
                  _DarkPillButton(
                    label: "Full Map",
                    icon: Icons.fullscreen_rounded,
                    onTap: onOpenFullMap,
                  ),
                  const SizedBox(width: 10),
                  _DarkPillButton(
                    label: "Close",
                    icon: Icons.close,
                    onTap: onClose,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FullSearchMapScreen extends StatefulWidget {
  final LatLng center;
  final LatLng? myLocation;
  final List<SeekerServiceUi> results;
  final SeekerNavController nav;

  const FullSearchMapScreen({
    super.key,
    required this.center,
    required this.myLocation,
    required this.results,
    required this.nav,
  });

  @override
  State<FullSearchMapScreen> createState() => _FullSearchMapScreenState();
}

class _FullSearchMapScreenState extends State<FullSearchMapScreen> {
  GoogleMapController? _c;

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    markers.add(
      Marker(
        markerId: const MarkerId("main_address"),
        position: widget.center,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: "Main Address"),
      ),
    );

    if (widget.myLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("me"),
          position: widget.myLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: "You"),
        ),
      );
    }

    for (final s in widget.results) {
      if (s.lat == null || s.lng == null) continue;

      final finalPrice = (s.price.toDouble() *
          (1.0 - s.discount.toDouble().clamp(0.0, 100.0) / 100.0))
          .clamp(0.0, 1e12);

      markers.add(
        Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.lat!, s.lng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: s.name,
            snippet: "RM ${finalPrice.toStringAsFixed(0)} • Tap to view",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ServiceDetailsScreen.fromServiceId(
                    nav: widget.nav,
                    serviceId: s.id,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return markers;
  }

  void _fitBounds() {
    if (_c == null) return;

    final points = <LatLng>[];

    points.add(widget.center);

    if (widget.myLocation != null) points.add(widget.myLocation!);

    for (final s in widget.results) {
      if (s.lat == null || s.lng == null) continue;
      points.add(LatLng(s.lat!, s.lng!));
    }

    if (points.isEmpty) {
      _c!.animateCamera(CameraUpdate.newLatLngZoom(widget.center, 13));
      return;
    }

    if (points.length == 1) {
      _c!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      minLat = _m.min(minLat, p.latitude);
      maxLat = _m.max(maxLat, p.latitude);
      minLng = _m.min(minLng, p.longitude);
      maxLng = _m.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _c!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  @override
  Widget build(BuildContext context) {
    final camTarget = widget.center;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: camTarget, zoom: 13),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              compassEnabled: true,
              markers: _buildMarkers(),
              onMapCreated: (c) {
                _c = c;
                WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
              },
            ),

            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        shape: BoxShape.circle,
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: const Icon(Icons.arrow_back, color: KLPalette.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.map_outlined, size: 18, color: KLPalette.text2),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Services Map (${widget.results.length})",
                              style: const TextStyle(fontWeight: FontWeight.w900),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: 12,
              bottom: 84,
              child: _MapLegend(
                showMePin: widget.myLocation != null,
                showGpsDot: true,
              ),
            ),

            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: KLPalette.tint100,
                          foregroundColor: KLPalette.text,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: _fitBounds,
                        child: const Text("Fit pins", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: KLPalette.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: () {
                          _c?.animateCamera(CameraUpdate.newLatLngZoom(widget.center, 14));
                        },
                        child: const Text("Recenter", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkPillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DarkPillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: KLPalette.darkPill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  final bool showMain;
  final bool showMePin;
  final bool showGpsDot;
  final bool showServices;

  const _MapLegend({
    this.showMain = true,
    this.showMePin = true,
    this.showGpsDot = true,
    this.showServices = true,
  });

  Widget _pin(Color c) => Icon(Icons.location_on, size: 18, color: c);

  Widget _dot(Color c) => Container(
    height: 10,
    width: 10,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
  );

  Widget _row(Widget icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 18, child: Center(child: icon)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          border: Border.all(color: KLPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Legend", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 6),
            if (showMain) _row(_pin(Colors.green), "Main Address (green pin)"),
            if (showMePin) _row(_pin(Colors.blue), "You (blue pin)"),
            if (showGpsDot) _row(_dot(Colors.blue), "GPS location (blue dot)"),
            if (showServices) _row(_pin(Colors.red), "Services (red pin)"),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final SeekerNavController nav;
  final SeekerServiceUi service;
  final bool saved;

  const _ResultCard({
    required this.nav,
    required this.service,
    required this.saved,
  });

  @override
  Widget build(BuildContext context) {
    final s = service;

    final finalPrice = (s.price.toDouble() *
        (1.0 - s.discount.toDouble().clamp(0.0, 100.0) / 100.0))
        .clamp(0.0, 1e12);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDetailsScreen.fromServiceId(
              nav: nav,
              serviceId: s.id,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: KLPalette.border),
            color: KLPalette.bg,
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _SeekerServiceCoverImage(service: s),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Icon(
                        saved ? Icons.bookmark : Icons.bookmark_border,
                        color: Colors.white,
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.90),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 6),
                            Text(s.rating.toStringAsFixed(1),
                                style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text("RM ${finalPrice.toStringAsFixed(0)}",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- FILTERS + HAVERSINE ---------------- */

class SearchFilters {
  final bool nearbyOnly;
  final double radiusKm;

  final String? categoryKey;

  final int? minPrice;
  final int? maxPrice;
  final int? minRating;

  final bool resetAll;

  const SearchFilters({
    this.nearbyOnly = false,
    this.radiusKm = 5,
    this.categoryKey,
    this.minPrice,
    this.maxPrice,
    this.minRating,
    this.resetAll = false,
  });

  bool get hasActiveFilters =>
      nearbyOnly || categoryKey != null || minPrice != null || maxPrice != null || minRating != null;

  SearchFilters copyWith({
    bool? nearbyOnly,
    double? radiusKm,
    String? categoryKey,
    int? minPrice,
    int? maxPrice,
    int? minRating,
    bool clearCategory = false,
    bool clearPrice = false,
    bool clearRating = false,
  }) {
    return SearchFilters(
      nearbyOnly: nearbyOnly ?? this.nearbyOnly,
      radiusKm: radiusKm ?? this.radiusKm,
      categoryKey: clearCategory ? null : (categoryKey ?? this.categoryKey),
      minPrice: clearPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPrice ? null : (maxPrice ?? this.maxPrice),
      minRating: clearRating ? null : (minRating ?? this.minRating),
      resetAll: false,
    );
  }
}

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);

  final a = (_m.sin(dLat / 2) * _m.sin(dLat / 2)) +
      _m.cos(_deg2rad(lat1)) * _m.cos(_deg2rad(lat2)) * (_m.sin(dLng / 2) * _m.sin(dLng / 2));

  final c = 2 * _m.atan2(_m.sqrt(a), _m.sqrt(1 - a));
  return r * c;
}

double _deg2rad(double deg) => deg * (3.141592653589793 / 180.0);

/* ---------------- small UI choices ---------------- */

class _CategoryCircleChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryCircleChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? KLPalette.primary : KLPalette.bg;
    final fg = selected ? Colors.white : KLPalette.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: Icon(icon, color: fg),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StarPillChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StarPillChoice({
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 18, color: selected ? Colors.white : KLPalette.text2),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : KLPalette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _defaultAssetForCategory(String category) {
  final c = category.toLowerCase().trim();

  if (c.contains('clean')) return 'assets/images/defaults/cleaning.jpg';
  if (c.contains('plumb')) return 'assets/images/defaults/plumbing.jpg';
  if (c.contains('handyman') || c.contains('repair')) {
    return 'assets/images/defaults/handyman.jpg';
  }
  if (c.contains('air') || c.contains('cond') || c.contains('aircon')) {
    return 'assets/images/defaults/aircon.jpg';
  }
  if (c.contains('tutor') || c.contains('lesson')) {
    return 'assets/images/defaults/tutoring.jpg';
  }

  return 'assets/images/defaults/handyman.jpg';
}

String? _bestSeekerServiceImageUrl(SeekerServiceUi s) {
  final t = ((s.thumbnailUrl ?? '') as String).trim();
  if (t.isNotEmpty) return t;

  final photos = (s.photoUrls ?? const <String>[]);
  if (photos.isNotEmpty) {
    final first = photos.first.trim();
    if (first.isNotEmpty) return first;
  }
  return null;
}

class _SeekerServiceCoverImage extends StatelessWidget {
  final SeekerServiceUi service;
  const _SeekerServiceCoverImage({required this.service});

  @override
  Widget build(BuildContext context) {
    final url = _bestSeekerServiceImageUrl(service);
    final fallbackAsset = _defaultAssetForCategory(service.category);

    if (url == null) {
      return Image.asset(fallbackAsset, fit: BoxFit.cover);
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: KLPalette.tint50,
          alignment: Alignment.center,
          child: const Icon(Icons.image, color: KLPalette.text2, size: 54),
        );
      },
      errorBuilder: (context, error, stack) {
        return Image.asset(fallbackAsset, fit: BoxFit.cover);
      },
    );
  }
}

class SeekerSearchHistoryRepo {
  static const String _usersCol = "users";

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _myRef(String uid) =>
      _db.collection(_usersCol).doc(uid);

  Stream<List<String>> streamMyHistory({int limit = 10}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <String>[]);

    return _myRef(uid).snapshots().map((snap) {
      final data = snap.data();
      final list = (data?["recentSearches"] as List?) ?? const [];
      final items = list.whereType<String>().toList();
      return items.take(limit).toList();
    });
  }

  Future<void> bump(String raw, {int limit = 10}) async {
    final q = raw.trim();
    if (q.isEmpty) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final ref = _myRef(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = (snap.data() as Map<String, dynamic>?) ?? <String, dynamic>{};

      final existing = ((data["recentSearches"] as List?) ?? const [])
          .whereType<String>()
          .toList();

      final lower = q.toLowerCase();
      final next = <String>[
        q,
        ...existing.where((e) => e.toLowerCase() != lower),
      ].take(limit).toList();

      tx.set(
        ref,
        {
          "recentSearches": next,
          "recentSearchesUpdatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> remove(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final ref = _myRef(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = (snap.data() as Map<String, dynamic>?) ?? <String, dynamic>{};

      final existing = ((data["recentSearches"] as List?) ?? const [])
          .whereType<String>()
          .toList();

      final lower = q.toLowerCase();
      final next = existing.where((e) => e.toLowerCase() != lower).toList();

      tx.set(ref, {"recentSearches": next}, SetOptions(merge: true));
    });
  }

  Future<void> clear() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _myRef(uid).set(
      {"recentSearches": <String>[]},
      SetOptions(merge: true),
    );
  }
}
