import 'package:flutter/material.dart';
import 'package:fyp_flutter/seeker_nav_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'seeker_services_repo.dart';
import 'booking_details_screen.dart';
import 'theme.dart';
import 'all_reviews_screen.dart';
import 'package:fyp_flutter/pricing/dynamic_pricing.dart';
import 'package:fyp_flutter/ui/service_pricing_vm.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'service_photo_gallery_screen.dart';

class ServiceDetailsScreen extends StatefulWidget {
  final String serviceId;
  final SeekerNavController nav;

  const ServiceDetailsScreen.fromServiceId({
    super.key,
    required this.serviceId,
    required this.nav,
  });

  @override
  State<ServiceDetailsScreen> createState() => _ServiceDetailsScreenState();
}

  class _ServiceDetailsScreenState extends State<ServiceDetailsScreen> {
  bool _loggedView = false;

  Future<void> _logViewOnce(SeekerServiceUi s) async {
    if (_loggedView) return;
      _loggedView = true;

    final uid = FirebaseAuth.instance.currentUser?.uid;

    await FirebaseFirestore.instance.collection('service_view_events').add({
    'serviceId': s.id,
    'providerId': s.providerId,
    'category': s.category,
    'seekerId': uid,
    'viewedAt': FieldValue.serverTimestamp(),
    'isSynthetic': false,
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SeekerServiceUi?>(
      stream: SeekerServicesRepo().streamById(widget.serviceId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: KLPalette.bg,
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        final s = snap.data;
        if (s == null) {
          return const Scaffold(
            backgroundColor: KLPalette.bg,
            body: SafeArea(child: Center(child: Text("Service not found"))),
          );
        }

        _logViewOnce(s);

        final pricing = ServicePricingVM.fromSeekerService(s);

        final priceLabel = pricing.discountPct > 0 ? "After discount" : "Base price";

        final photos = s.photoUrls;
        final heroUrl = s.thumbnailUrl ?? (photos.isNotEmpty ? photos.first : null);

        final uiModel = ServiceDetailsUiModel(
          title: s.name,
          category: s.category,
          location: s.address,
          heroTag: s.featured ? "Featured Service" : "Service",
          photosCount: photos.length,
          photos: photos,
          heroUrl: heroUrl,
          price: pricing.finalPackage,
          priceLabel: priceLabel,
          basePrice: pricing.basePrice,
          discountPct: pricing.discountPct,
          savedAmount: pricing.savedAmount,
          durationLabel: pricing.durationLabel,
          durationH: pricing.durationH,
          durationM: pricing.durationM,
          hourlyRate: pricing.hourlyRate,
          rating: s.rating,
          reviewCount: s.ratingCount,
          description: (s.description.trim().isNotEmpty) ? s.description : "No description provided.",
          whyRecommended: [
            if (s.featured) "Featured",
            if (s.type == "onsite") "On-site",
            if (s.type == "remote") "Remote",
          ],
          reviewsPreview: const [],
        );

        return _ServiceDetailsScaffold(
          model: uiModel,
          nav: widget.nav,
          serviceId: s.id,
          providerId: s.providerId,
          providerLat: s.lat,
          providerLng: s.lng,
          hourlyRate: s.hourlyRate,
          pricingRules: s.pricingRules,
          pricingCaps: s.pricingCaps,
          sentimentScore: s.sentimentScore,
          topKeywords: s.topKeywords,
          reviewsAnalyzed: s.reviewsAnalyzed,
        );
      },
    );
  }

  static void _showPriceBreakdown(
      BuildContext context, {
        required double basePrice,
        required double discountPercent,
        required int includedMinutes,
        required double hourlyRate,
        required List<Map<String, dynamic>> pricingRules,
        required Map<String, dynamic>? pricingCaps,
      }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        int hours = 2;
        // quick preview toggles
        bool isWeekend = false;
        bool isEvening = false;
        bool isFar = false;

        bool hasDaysRule(List<Map<String, dynamic>> rules) {
          return rules.any((r) {
            final when = (r["when"] as Map?)?.cast<String, dynamic>() ?? const {};
            final days = when["days"] as List?;
            return days != null && days.isNotEmpty;
          });
        }

        bool hasTimeRule(List<Map<String, dynamic>> rules) {
          return rules.any((r) {
            final when = (r["when"] as Map?)?.cast<String, dynamic>() ?? const {};
            return when["startHour"] != null || when["endHour"] != null;
          });
        }

        double? distanceThreshold(List<Map<String, dynamic>> rules) {
          double? best;
          for (final r in rules) {
            final when = (r["when"] as Map?)?.cast<String, dynamic>() ?? const {};
            final minD = (when["minDistanceKm"] as num?)?.toDouble();
            final maxD = (when["maxDistanceKm"] as num?)?.toDouble();
            final candidate = minD ?? maxD;
            if (candidate == null) continue;
            best = (best == null) ? candidate : (candidate < best! ? candidate : best);
          }
          return best;
        }

        PricingQuote compute() {
          final now = DateTime.now();
          DateTime baseDate = DateTime(now.year, now.month, now.day, isEvening ? 19 : 10);

          // make it weekend if toggled
          if (isWeekend) {
            // find next Saturday
            final daysUntilSat = (DateTime.saturday - baseDate.weekday + 7) % 7;
            baseDate = baseDate.add(Duration(days: daysUntilSat == 0 ? 7 : daysUntilSat));
          } else {
            // make it weekday (next Monday) to avoid weekend rule
            final daysUntilMon = (DateTime.monday - baseDate.weekday + 7) % 7;
            baseDate = baseDate.add(Duration(days: daysUntilMon == 0 ? 7 : daysUntilMon));
          }

          final distTh = distanceThreshold(pricingRules);

          final ctx = PricingContext(
            scheduledAt: baseDate,
            minutes: hours * 60,
            distanceKm: (distTh == null) ? 1.0 : (isFar ? distTh : 1.0),
          );

          return evaluatePricing(
            floorPrice: 0,
            packagePrice: basePrice,
            includedMinutes: includedMinutes,
            hourlyRate: hourlyRate,
            discountPercent: discountPercent,
            ctx: ctx,
            rules: pricingRules,
            caps: pricingCaps,
          );
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final showWeekend = hasDaysRule(pricingRules);
            final showEvening = hasTimeRule(pricingRules);
            final distTh = distanceThreshold(pricingRules);

            final scheduledAt = _previewScheduledAt(isWeekend: isWeekend, isEvening: isEvening);
            final quote = evaluatePricing(
              floorPrice: 0,
              packagePrice: basePrice,
              includedMinutes: includedMinutes,
              hourlyRate: hourlyRate,
              discountPercent: discountPercent,
              ctx: PricingContext(
                scheduledAt: scheduledAt,
                minutes: hours * 60,
                distanceKm: (distTh == null) ? 1.0 : (isFar ? distTh : 1.0),
              ),
              rules: pricingRules,
              caps: pricingCaps,
            );

            final selectedMinutes = hours * 60;
            final extraMinutes =
            (selectedMinutes - includedMinutes).clamp(0, 1 << 30).toInt();
            final extraHours = extraMinutes / 60.0;

            String fmtHM(int mins) {
              final h = mins ~/ 60;
              final m = mins % 60;
              if (m == 0) return "${h}h";
              if (h == 0) return "${m}m";
              return "${h}h ${m}m";
            }

            final extraLabel = extraMinutes <= 0
                ? "Extra time"
                : "Extra time (${fmtHM(extraMinutes)} × RM ${hourlyRate.toStringAsFixed(0)}/hr)";

            // keep compute referenced (optional) to avoid "unused" warnings in some configs
            // ignore: unused_local_variable
            final _ = compute;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
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
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Transparent pricing",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // --- Preview Controls ---
                    _PreviewRow(
                      label: "Hours",
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _miniBtn(
                            icon: Icons.remove,
                            onTap: hours <= 1 ? null : () => setModalState(() => hours--),
                          ),
                          const SizedBox(width: 10),
                          Text("$hours", style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(width: 10),
                          _miniBtn(
                            icon: Icons.add,
                            onTap: hours >= 24 ? null : () => setModalState(() => hours++),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (showWeekend)
                          _toggleChip(
                            label: isWeekend ? "Weekend (on)" : "Weekend (off)",
                            on: isWeekend,
                            onTap: () => setModalState(() => isWeekend = !isWeekend),
                          ),
                        if (showEvening)
                          _toggleChip(
                            label: isEvening ? "Evening (on)" : "Evening (off)",
                            on: isEvening,
                            onTap: () => setModalState(() => isEvening = !isEvening),
                          ),
                        if (distTh != null)
                          _toggleChip(
                            label: isFar
                                ? "Far ≥${distTh.toStringAsFixed(0)}km (on)"
                                : "Far ≥${distTh.toStringAsFixed(0)}km (off)",
                            on: isFar,
                            onTap: () => setModalState(() => isFar = !isFar),
                          ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Preview time: ${_fmtPreviewTime(scheduledAt)}",
                        style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // --- Breakdown ---
                    _LineItem(label: "Package price", value: "RM ${basePrice.toStringAsFixed(2)}"),
                    _LineItem(label: "Included duration", value: fmtHM(includedMinutes)),
                    _LineItem(label: "Selected duration", value: fmtHM(selectedMinutes)),

                    if (extraMinutes > 0)
                      _LineItem(
                        label: extraLabel,
                        value: "RM ${quote.hoursAmount.toStringAsFixed(2)}",
                      ),

                    ...quote.lines.map(
                          (l) => _LineItem(
                        label: l.label,
                        value: "${l.amount >= 0 ? '+' : '-'}RM ${l.amount.abs().toStringAsFixed(2)}",
                      ),
                    ),

                    const Divider(color: KLPalette.border),
                    _LineItem(
                      label: "Estimated total",
                      value: "RM ${quote.total.toStringAsFixed(2)}",
                      bold: true,
                    ),

                    const SizedBox(height: 16),

                    // --- Rules list ---
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Pricing rules in this service",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (pricingRules.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "No pricing rules configured.",
                          style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      Column(
                        children: pricingRules.map((r) {
                          final applies = _ruleApplies(
                            rule: r,
                            floorPrice: 0,
                            hourlyRate: hourlyRate,
                            hours: hours,
                            scheduledAt: scheduledAt,
                            distanceKm: (distTh == null) ? 1.0 : (isFar ? distTh : 1.0),
                            caps: pricingCaps,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RuleCard(
                              rule: r,
                              appliesNow: applies,
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static DateTime _previewScheduledAt({required bool isWeekend, required bool isEvening}) {
    final now = DateTime.now();
    var base = DateTime(now.year, now.month, now.day, isEvening ? 19 : 10);

    if (isWeekend) {
      final daysUntilSat = (DateTime.saturday - base.weekday + 7) % 7;
      base = base.add(Duration(days: daysUntilSat == 0 ? 7 : daysUntilSat));
    } else {
      final daysUntilMon = (DateTime.monday - base.weekday + 7) % 7;
      base = base.add(Duration(days: daysUntilMon == 0 ? 7 : daysUntilMon));
    }
    return base;
  }

  static String _fmtPreviewTime(DateTime dt) {
    final wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][dt.weekday - 1];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return "$wd $hh:$mm";
  }

  static bool _ruleApplies({
    required Map<String, dynamic> rule,
    required double floorPrice,
    required double hourlyRate,
    required int hours,
    required DateTime scheduledAt,
    required double distanceKm,
    required Map<String, dynamic>? caps,
  }) {
    final q = evaluatePricing(
      floorPrice: floorPrice,
      packagePrice: 0,
      includedMinutes: 0,
      hourlyRate: hourlyRate,
      discountPercent: 0,
      ctx: PricingContext(
        scheduledAt: scheduledAt,
        minutes: hours * 60,
        distanceKm: distanceKm,
      ),
      rules: [rule],
      caps: caps,
    );
    return q.lines.isNotEmpty;
  }

  static Widget _miniBtn({required IconData icon, required VoidCallback? onTap}) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Opacity(
        opacity: disabled ? 0.35 : 1,
        child: Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: KLPalette.mutedBg,
            shape: BoxShape.circle,
            border: Border.all(color: KLPalette.border),
          ),
          child: Icon(icon, size: 18, color: KLPalette.text),
        ),
      ),
    );
  }

  static Widget _toggleChip({required String label, required bool on, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on ? KLPalette.tint50 : KLPalette.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? KLPalette.primary : KLPalette.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: on ? KLPalette.primary : KLPalette.text,
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _PreviewRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        child,
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  final Map<String, dynamic> rule;
  final bool appliesNow;

  const _RuleCard({required this.rule, required this.appliesNow});

  @override
  Widget build(BuildContext context) {
    final label = (rule["label"] ?? rule["id"] ?? "Rule").toString();
    final when = (rule["when"] as Map?)?.cast<String, dynamic>() ?? const {};
    final desc = _describeWhen(when);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              appliesNow ? Icons.check_circle_rounded : Icons.info_outline,
              color: appliesNow ? KLPalette.primary : KLPalette.text2,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(
                      color: KLPalette.text2,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: appliesNow ? KLPalette.tint50 : KLPalette.mutedBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: KLPalette.border),
              ),
              child: Text(
                appliesNow ? "Applied" : "Not now",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: appliesNow ? KLPalette.primary : KLPalette.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _describeWhen(Map<String, dynamic> when) {
    final parts = <String>[];

    final days = (when["days"] as List?)
        ?.cast<dynamic>()
        .map((e) => (e as num).toInt())
        .toList();
    if (days != null && days.isNotEmpty) {
      // your doc uses [6,7] for weekend (Sat/Sun in DateTime.weekday)
      final isWeekend = days.contains(6) && days.contains(7) && days.length == 2;
      if (isWeekend) {
        parts.add("Applies on weekends");
      } else {
        parts.add("Applies on days: ${days.join(', ')}");
      }
    }

    final sh = (when["startHour"] as num?)?.toInt();
    final eh = (when["endHour"] as num?)?.toInt();
    if (sh != null && eh != null) {
      parts.add(
        "Applies between ${sh.toString().padLeft(2, '0')}:00–${eh.toString().padLeft(2, '0')}:59",
      );
    }

    final minD = (when["minDistanceKm"] as num?)?.toDouble();
    if (minD != null) {
      parts.add("Applies when distance ≥ ${minD.toStringAsFixed(0)} km");
    }

    if (parts.isEmpty) return "Always applies";
    return parts.join(" • ");
  }
}

class _ServiceDetailsScaffold extends StatelessWidget {
  final ServiceDetailsUiModel model;
  final SeekerNavController nav;
  final String serviceId;
  final String providerId;
  final double? providerLat;
  final double? providerLng;
  final double hourlyRate;
  final List<Map<String, dynamic>> pricingRules;
  final Map<String, dynamic>? pricingCaps;

  final double? sentimentScore;
  final List<String> topKeywords;
  final int? reviewsAnalyzed;

  const _ServiceDetailsScaffold({
    required this.model,
    required this.nav,
    required this.serviceId,
    required this.providerId,
    required this.providerLat,
    required this.providerLng,
    required this.hourlyRate,
    required this.pricingRules,
    required this.pricingCaps,
    this.sentimentScore,
    this.topKeywords = const [],
    this.reviewsAnalyzed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _TopBar(
                  title: "Service Detail",
                  onBack: () => Navigator.pop(context),
                  onShare: () {},
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _HeroImageCard(
                  url: model.heroUrl,
                  onTap: (model.photos.isEmpty)
                      ? null
                      : () {
                    final initial = model.heroUrl == null
                        ? 0
                        : model.photos
                        .indexOf(model.heroUrl!)
                        .clamp(0, model.photos.length - 1)
                        .toInt();

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServicePhotoGalleryScreen(
                          urls: model.photos,
                          initialIndex: initial,
                        ),
                      ),
                    );
                  },
                ),
              ),

            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverToBoxAdapter(child: _HeaderBlock(model: model)),
            ),

            // v2: sentiment + keywords section (shown only when data exists)
            if (sentimentScore != null || topKeywords.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _InsightsBlock(
                    sentimentScore: sentimentScore,
                    topKeywords: topKeywords,
                    reviewsAnalyzed: reviewsAnalyzed,
                  ),
                ),
              ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _DescriptionBlock(text: model.description),
              ),
            ),

            // Photos section
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _SectionRow(
                  title: "Photos",
                  actionText: "View All",
                  onTap: () {
                    if (model.photos.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServicePhotoGalleryScreen(urls: model.photos, initialIndex: 0),
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: InkWell(
                  onTap: () {
                    if (model.photos.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServicePhotoGalleryScreen(urls: model.photos, initialIndex: 0),
                      ),
                    );
                  },
                  child: _PhotosGrid(urls: model.photos),
                ),
              ),
            ),

            // Reviews section
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _SectionRow(
                  title: "Reviews",
                  leadingStarValue: model.rating,
                  actionText: "View All",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AllReviewsScreen(serviceId: serviceId),
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: StreamBuilder<List<ServiceReview>>(
                  stream: streamServiceReviewsPreview(serviceId, limit: 3),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final reviews = snap.data ?? [];

                    if (reviews.isEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: KLPalette.bg,
                            border: Border.all(color: KLPalette.border),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: const Text(
                            "No reviews yet.",
                            style: TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        for (int i = 0; i < reviews.length; i++) ...[
                          ReviewCard(
                            review: ReviewUiModel(
                              name: reviews[i].name,
                              dateText: _reviewDateText(reviews[i].createdAt),
                              rating: reviews[i].stars.toDouble(),
                              text: reviews[i].text,
                              verifiedJob: reviews[i].verifiedJob,
                            ),
                          ),
                          if (i != reviews.length - 1) const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),

            // bottom spacing for CTA bar
            SliverToBoxAdapter(
              child: SizedBox(
                height: 120 + MediaQuery.of(context).padding.bottom,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _BottomCtaBar(
          onChat: () {},
          onBookNow: () {
            final service = BookedServiceUi(
              id: serviceId,
              providerId: providerId,
              title: model.title,
              location: model.location,
              rating: model.rating,
              floorPrice: model.price,
              hourlyRate: hourlyRate,
              basePrice: model.basePrice,
              discountPct: model.discountPct,
              durationH: model.durationH,
              durationM: model.durationM,
              pricingRules: pricingRules,
              pricingCaps: pricingCaps,
              providerLat: providerLat,
              providerLng: providerLng,
            );

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BookingDetailsScreen(service: service, nav: nav),
              ),
            );
          },
          onPriceInfo: () => _ServiceDetailsScreenState._showPriceBreakdown(
            context,
            basePrice: model.basePrice,
            discountPercent: model.discountPct,
            includedMinutes: model.durationH * 60 + model.durationM,
            hourlyRate: hourlyRate,
            pricingRules: pricingRules,
            pricingCaps: pricingCaps,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back, onTap: onBack),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const Spacer(),
        const SizedBox(width: 48),
        // _CircleButton(icon: Icons.ios_share_rounded, onTap: onShare),
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

class _HeroImageCard extends StatelessWidget {
  final String? url;
  final VoidCallback? onTap;

  const _HeroImageCard({this.url, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 230,
          decoration: BoxDecoration(
            color: KLPalette.mutedBg,
            border: Border.all(color: KLPalette.border),
          ),
          child: _NetImage(
            url: url,
            fit: BoxFit.cover,
            placeholderIcon: Icons.image,
            big: true,
          ),
        ),
      ),
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  final ServiceDetailsUiModel model;

  const _HeaderBlock({required this.model});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          model.heroTag,
          style: const TextStyle(
            color: KLPalette.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                model.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 34,
                  height: 1.05,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        const SizedBox(height: 12),

        // Price + rating row
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (model.discountPct > 0)
                  Text(
                    ServicePricingVM.rm(model.basePrice, decimals: 2),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: KLPalette.text2,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  ServicePricingVM.rm(model.price, decimals: 2),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
                ),
              ],
            ),

            if (model.discountPct > 0) ...[
              const SizedBox(width: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: KLPalette.tint50,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: KLPalette.border),
                ),
                child: Text(
                  "Save ${ServicePricingVM.rm(model.savedAmount, decimals: 2)}",
                  style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary),
                ),
              ),
            ],
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                  const SizedBox(width: 4),
                  Text(
                    model.rating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      "(${_compactReviewCount(model.reviewCount)} Reviews)",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Category + location
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Chip(label: model.category),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: KLPalette.text,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    model.location,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),

        // “Why recommended” chips
        if (model.whyRecommended.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: model.whyRecommended.map((s) => _SoftPill(label: s)).toList(),
          ),
        ],
      ],
    );
  }
}

class _InsightsBlock extends StatelessWidget {
  final double? sentimentScore; // expected 0..100 (or null)
  final List<String> topKeywords;
  final int? reviewsAnalyzed;

  const _InsightsBlock({
    required this.sentimentScore,
    required this.topKeywords,
    this.reviewsAnalyzed,
  });

  static String _sentimentLabel(double s) {
    if (s >= 85) return "Excellent";
    if (s >= 70) return "Good";
    if (s >= 55) return "Okay";
    if (s >= 40) return "Mixed";
    return "Poor";
  }

  static void _showSentimentInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "About review sentiment",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            SizedBox(height: 10),
            Text(
              "This is an AI-generated summary of customer reviews.\n\n"
                  "• Scale: 0–100 (higher = more positive)\n"
                  "• It combines star ratings and review text\n"
                  "• It helps you quickly compare services, but it’s not a guarantee\n\n"
                  "Tip: Read the full reviews for context.",
              style: TextStyle(
                color: KLPalette.text2,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _titleCase(String s) {
    final parts = s.trim().split(RegExp(r"\s+")).where((e) => e.isNotEmpty).toList();
    return parts
        .map((w) => w.isEmpty ? w : "${w[0].toUpperCase()}${w.substring(1)}")
        .join(" ");
  }

  @override
  Widget build(BuildContext context) {
    final s = (sentimentScore ?? 0).clamp(0, 100).toDouble();
    final label = _sentimentLabel(s);

    final n = (reviewsAnalyzed ?? 0);
    final basedOnText = n > 0 ? "Based on $n review${n == 1 ? "" : "s"}" : null;

    final cleanKeywords = topKeywords
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(_titleCase)
        .toSet()
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Insights",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const Spacer(),
                if (basedOnText != null)
                  Text(
                    basedOnText,
                    style: const TextStyle(
                      color: KLPalette.text2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (sentimentScore != null) ...[
              Row(
                children: [
                  const Text(
                    "Review sentiment",
                    style: TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _showSentimentInfo(context),
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.info_outline, size: 18, color: KLPalette.text2),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "${s.toStringAsFixed(0)}/100",
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SentimentBar(score: s),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: KLPalette.tint50,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: KLPalette.border),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: KLPalette.primary,
                  ),
                ),
              ),
            ],

            if (sentimentScore != null && cleanKeywords.isNotEmpty) const SizedBox(height: 14),

            if (cleanKeywords.isNotEmpty) ...[
              const Text(
                "What people say",
                style: TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: cleanKeywords.take(12).map((k) => _SoftPill(label: k)).toList(),
              ),
            ],

            if (sentimentScore == null && cleanKeywords.isEmpty)
              const Text(
                "No insights available yet.",
                style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }
}

class _DescriptionBlock extends StatefulWidget {
  final String text;

  const _DescriptionBlock({required this.text});

  @override
  State<_DescriptionBlock> createState() => _DescriptionBlockState();
}

class _DescriptionBlockState extends State<_DescriptionBlock> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.text,
      maxLines: expanded ? 50 : 3,
      overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      style: const TextStyle(
        color: KLPalette.text2,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final String title;
  final String actionText;
  final VoidCallback onTap;
  final double? leadingStarValue;

  const _SectionRow({
    required this.title,
    required this.actionText,
    required this.onTap,
    this.leadingStarValue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        if (leadingStarValue != null) ...[
          const SizedBox(width: 10),
          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 22),
          const SizedBox(width: 4),
          Text(
            leadingStarValue!.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ],
        const Spacer(),
        InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Text(
                actionText,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  final List<String> urls;

  const _PhotosGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    final total = urls.length;

    Widget photoBox(String? url) {
      return _NetImage(
        url: url,
        fit: BoxFit.cover,
        placeholderIcon: Icons.image,
      );
    }

    final u0 = total > 0 ? urls[0] : null;
    final u1 = total > 1 ? urls[1] : null;
    final u2 = total > 2 ? urls[2] : null;

    final showOverlay = total > 3;
    final overlayText = "${(total - 2).clamp(1, 99)}+";

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(height: 190, child: photoBox(u0)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(height: 90, child: photoBox(u1)),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    SizedBox(height: 90, width: double.infinity, child: photoBox(u2)),
                    if (showOverlay) ...[
                      Positioned.fill(child: Container(color: Colors.black.withOpacity(0.25))),
                      Positioned.fill(
                        child: Center(
                          child: Text(
                            overlayText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 34,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomCtaBar extends StatelessWidget {
  final VoidCallback onChat;
  final VoidCallback onBookNow;
  final VoidCallback onPriceInfo;

  const _BottomCtaBar({
    required this.onChat,
    required this.onBookNow,
    required this.onPriceInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: KLPalette.bg,
        border: Border(top: BorderSide(color: KLPalette.border)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onChat,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: KLPalette.bg,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: KLPalette.text,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: KLPalette.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: onBookNow,
                child: const Text(
                  "Book Now",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // small info button (pricing)
          InkWell(
            onTap: onPriceInfo,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: KLPalette.tint50,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: const Icon(Icons.receipt_long, color: KLPalette.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewCard extends StatelessWidget {
  final ReviewUiModel review;

  const ReviewCard({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(radius: 22, backgroundColor: KLPalette.tint50),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          review.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 6),
                      Text(
                        review.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.more_vert, color: KLPalette.text2),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        review.dateText,
                        style: const TextStyle(
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (review.verifiedJob) ...[
                        const SizedBox(width: 10),
                        _VerifiedBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    review.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
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

class _VerifiedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KLPalette.tint50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 16, color: KLPalette.primary),
          SizedBox(width: 6),
          Text(
            "Verified",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: KLPalette.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KLPalette.tint50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: KLPalette.primary,
        ),
      ),
    );
  }
}

class _SoftPill extends StatelessWidget {
  final String label;

  const _SoftPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KLPalette.mutedBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _LineItem extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _LineItem({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
      fontSize: bold ? 16 : 14,
      color: bold ? KLPalette.text : KLPalette.text2,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

// --- v2 UI bits ---

class _SentimentBar extends StatelessWidget {
  final double score; // 0..100
  const _SentimentBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final double pct = (score / 100.0).clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: KLPalette.mutedBg,
          border: Border.all(color: KLPalette.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: pct,
            child: Container(
              decoration: BoxDecoration(
                color: KLPalette.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- UI Models ---

class ServiceDetailsUiModel {
  final String heroTag;
  final String title;
  final String category;
  final String location;
  final String? heroUrl;
  final List<String> photos;
  final double price;
  final String priceLabel;
  final double basePrice;
  final double discountPct;
  final double savedAmount;
  final String durationLabel;
  final int durationH;
  final int durationM;
  final double hourlyRate;
  final double rating;
  final int reviewCount;
  final String description;
  final List<String> whyRecommended;
  final int photosCount;
  final List<ReviewUiModel> reviewsPreview;

  ServiceDetailsUiModel({
    required this.heroTag,
    required this.title,
    required this.category,
    required this.location,
    this.heroUrl,
    required this.photos,
    required this.price,
    required this.priceLabel,
    required this.basePrice,
    required this.discountPct,
    required this.savedAmount,
    required this.durationLabel,
    required this.durationH,
    required this.durationM,
    required this.hourlyRate,
    required this.rating,
    required this.reviewCount,
    required this.description,
    required this.whyRecommended,
    required this.photosCount,
    required this.reviewsPreview,
  });
}

class ReviewUiModel {
  final String name;
  final String dateText;
  final double rating;
  final String text;
  final bool verifiedJob;

  ReviewUiModel({
    required this.name,
    required this.dateText,
    required this.rating,
    required this.text,
    this.verifiedJob = false,
  });
}

String _compactReviewCount(int n) {
  if (n >= 1000) return "${(n / 1000).toStringAsFixed(1)}k";
  return n.toString();
}

class _DemoPhoto extends StatelessWidget {
  final Color color;

  const _DemoPhoto({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: const Center(child: Icon(Icons.image, color: KLPalette.text2)),
    );
  }
}

class ServiceReview {
  final String name;
  final String text;
  final int stars;
  final DateTime? createdAt;
  final bool verifiedJob;

  ServiceReview({
    required this.name,
    required this.text,
    required this.stars,
    required this.createdAt,
    required this.verifiedJob,
  });

  static ServiceReview fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    return ServiceReview(
      name: (m['seekerName'] ?? 'Seeker').toString(),
      text: (m['text'] ?? '').toString(),
      stars: (m['stars'] is num) ? (m['stars'] as num).toInt() : 0,
      createdAt: (m['createdAt'] is Timestamp) ? (m['createdAt'] as Timestamp).toDate() : null,
      verifiedJob: (m['verifiedJob'] ?? false) == true,
    );
  }
}

Stream<List<ServiceReview>> streamServiceReviewsPreview(String serviceId, {int limit = 3}) {
  return FirebaseFirestore.instance
      .collection('services')
      .doc(serviceId)
      .collection('reviews')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snap) => snap.docs.map(ServiceReview.fromDoc).toList());
}

String _reviewDateText(DateTime? dt) {
  if (dt == null) return "—";
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  return "$dd/$mm/${dt.year}";
}

class _NetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final IconData placeholderIcon;
  final bool big;

  const _NetImage({
    this.url,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();

    Widget placeholder() => Container(
      color: KLPalette.mutedBg,
      alignment: Alignment.center,
      child: Icon(
        placeholderIcon,
        size: big ? 68 : 34,
        color: KLPalette.text2,
      ),
    );

    if (u.isEmpty) return placeholder();

    return Image.network(
      u,
      fit: fit,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => placeholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            placeholder(),
            Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                minHeight: 3,
                value: (progress.expectedTotalBytes == null)
                    ? null
                    : progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1),
              ),
            ),
          ],
        );
      },
    );
  }
}
