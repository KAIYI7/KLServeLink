import 'package:flutter/material.dart';
import 'package:fyp_flutter/pricing/dynamic_pricing.dart';
import 'package:fyp_flutter/ui/service_pricing_vm.dart';
import 'package:fyp_flutter/provider_service_analytics_screen.dart';
import 'package:fyp_flutter/utils/app_snack.dart';
import 'theme.dart';
import 'provider_service_form_screen.dart';
import 'data/provider_services_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'service_photo_gallery_screen.dart';

class ProviderServiceDetailScreen extends StatefulWidget {
  final ProviderServiceUi service;
  const ProviderServiceDetailScreen({super.key, required this.service});

  @override
  State<ProviderServiceDetailScreen> createState() => _ProviderServiceDetailScreenState();
}

class _ProviderServiceDetailScreenState extends State<ProviderServiceDetailScreen> {
  final _repo = ProviderServicesRepo();
  bool _deleting = false;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete service?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      await _repo.safeDeleteService(widget.service.id);
      if (!mounted) return;

      Navigator.pop(context, "__deleted__");
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);

      if (e is StateError && e.message == "HAS_UPCOMING_BOOKINGS") {
        AppSnack.show(
          context,
          "You have upcoming bookings for this service. Complete or cancel them first.",
          type: AppSnackType.info,
        );
        return;
      }

      AppSnack.show(
        context,
        "Delete failed. Please try again.",
        type: AppSnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final p = ServicePricingVM.fromService(service);

    final photos = service.photoUrls;
    final heroUrl = service.thumbnailUrl ?? (photos.isNotEmpty ? photos.first : null);

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              _TopBar(
                title: "Service Detail",
                onBack: () => Navigator.pop(context),
                onEdit: _deleting
                    ? null
                    : () async {
                  final updated = await Navigator.push<ProviderServiceUi>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProviderServiceFormScreen(initial: service),
                    ),
                  );
                  if (updated != null && context.mounted) {
                    Navigator.pop(context, updated);
                  }
                },
                onDelete: _deleting ? null : _delete,
                deleting: _deleting,
              ),
              const SizedBox(height: 14),

              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: InkWell(
                  onTap: (photos.isEmpty)
                      ? null
                      : () {
                    final initial = heroUrl == null ? 0 : (photos.indexOf(heroUrl).clamp(0, photos.length - 1));
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServicePhotoGalleryScreen(urls: photos, initialIndex: initial),
                      ),
                    );
                  },
                  child: Container(
                    height: 230,
                    decoration: BoxDecoration(
                      color: KLPalette.mutedBg,
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: heroUrl == null
                        ? const Center(child: Icon(Icons.image, size: 68, color: KLPalette.text2))
                        : Image.network(heroUrl, fit: BoxFit.cover),
                  ),
                ),
              ),

              if (photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final u = photos[i];
                      final isHero = u == heroUrl;
                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ServicePhotoGalleryScreen(urls: photos, initialIndex: i),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 64,
                            decoration: BoxDecoration(
                              border: Border.all(color: isHero ? KLPalette.primary : KLPalette.border, width: isHero ? 2 : 1),
                            ),
                            child: Image.network(u, fit: BoxFit.cover),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      service.name,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 30, height: 1.05),
                    ),
                  ),
                  if (service.featured)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: KLPalette.tint100,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: const Text("Featured", style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700)),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Pill(text: service.category),
                  _Pill(text: service.address),
                  _Pill(text: service.type == ServiceType.onsite ? "On-site" : "Remote"),
                  _Pill(text: service.status == ServiceStatus.active ? "Active" : "Inactive"),
                ],
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p.discountPct > 0)
                        Text(
                          ServicePricingVM.rm(p.basePrice, decimals: 0),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: KLPalette.text2,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      Text(
                        ServicePricingVM.rm(p.finalPackage, decimals: 0),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  if (p.discountPct > 0) ...[
                    Text(
                      "-${p.discountPct.toStringAsFixed(0)}%",
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF16A34A)),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: KLPalette.tint50,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: Text(
                        "Save ${ServicePricingVM.rm(p.savedAmount, decimals: 0)}",
                        style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700),
                      ),
                    ),
                  ],
                  const Spacer(),
                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                  const SizedBox(width: 6),
                  Text(service.ratingAvg.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 12),

              InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProviderServiceAnalyticsScreen(service: service),
                    ),
                  );
                },
                child: ProviderServiceInsightsMini(
                  providerId: FirebaseAuth.instance.currentUser?.uid ?? "",
                  serviceId: service.id,
                ),
              ),

              const SizedBox(height: 14),
              _InkCard(
                title: "Pricing preview",
                subtitle: "See how rules + caps affect customer price",
                icon: Icons.receipt_long,
                onTap: () => _showProviderPricingPreview(context, service),
              ),

              const SizedBox(height: 12),

              _SectionTitle("Duration"),
              const SizedBox(height: 8),
              Text(
                p.durationLabel,
                style: const TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
              ),
              const SizedBox(height: 14),

              _SectionTitle("Description"),
              const SizedBox(height: 8),
              Text(
                service.description.isEmpty ? "—" : service.description,
                style: const TextStyle(fontWeight: FontWeight.w700, color: KLPalette.text2, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProviderPricingPreview(BuildContext context, ProviderServiceUi service) {
    final basePrice = service.price.toDouble(); // raw package price
    final discountPercent = service.discount.toDouble().clamp(0.0, 100.0);

    final includedMinutes = (service.durationHours * 60) + service.durationMins;
    final includedHours = includedMinutes / 60.0;

    final hourlyRate = (includedHours > 0) ? (basePrice / includedHours) : 0.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        int hours = 2;
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

        DateTime previewScheduledAt() {
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

        String fmtPreviewTime(DateTime dt) {
          final wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][dt.weekday - 1];
          final hh = dt.hour.toString().padLeft(2, '0');
          final mm = dt.minute.toString().padLeft(2, '0');
          return "$wd $hh:$mm";
        }

        bool ruleApplies(Map<String, dynamic> r, DateTime scheduledAt, double distanceKm) {
          final id = (r["id"] ?? "rule").toString();
          final q = evaluatePricing(
            floorPrice: 0,
            packagePrice: basePrice,
            includedMinutes: includedMinutes,
            hourlyRate: hourlyRate,
            discountPercent: discountPercent,
            ctx: PricingContext(
              scheduledAt: scheduledAt,
              minutes: hours * 60,
              distanceKm: distanceKm,
            ),
            rules: [r],
            caps: service.pricingCaps,
          );
          return q.lines.any((l) => l.ruleId == id);
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final showWeekend = hasDaysRule(service.pricingRules);
            final showEvening = hasTimeRule(service.pricingRules);
            final distTh = distanceThreshold(service.pricingRules);

            final scheduledAt = previewScheduledAt();
            final distanceKm = (distTh == null) ? 1.0 : (isFar ? distTh : 1.0);

            final quote = evaluatePricing(
              floorPrice: 0,
              packagePrice: basePrice,
              includedMinutes: includedMinutes,
              hourlyRate: hourlyRate,
              discountPercent: discountPercent,
              ctx: PricingContext(
                scheduledAt: scheduledAt,
                minutes: hours * 60,
                distanceKm: distanceKm,
              ),
              rules: service.pricingRules,
              caps: service.pricingCaps,
            );

            final selectedMinutes = hours * 60;
            final extraMinutes = (selectedMinutes - includedMinutes).clamp(0, 1 << 30).toInt();

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

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20, 14, 20, 24 + MediaQuery.of(context).viewInsets.bottom,
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
                        "Pricing preview",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Preview time: ${fmtPreviewTime(scheduledAt)} • Distance: ${distanceKm.toStringAsFixed(0)} km",
                        style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // controls
                    Row(
                      children: [
                        const Expanded(child: Text("Hours", style: TextStyle(fontWeight: FontWeight.w900))),
                        InkWell(
                          onTap: hours <= 1 ? null : () => setModalState(() => hours--),
                          borderRadius: BorderRadius.circular(999),
                          child: Opacity(
                            opacity: hours <= 1 ? 0.35 : 1,
                            child: Container(
                              height: 36, width: 36,
                              decoration: BoxDecoration(
                                color: KLPalette.mutedBg,
                                shape: BoxShape.circle,
                                border: Border.all(color: KLPalette.border),
                              ),
                              child: const Icon(Icons.remove, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text("$hours", style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: hours >= 24 ? null : () => setModalState(() => hours++),
                          borderRadius: BorderRadius.circular(999),
                          child: Opacity(
                            opacity: hours >= 24 ? 0.35 : 1,
                            child: Container(
                              height: 36, width: 36,
                              decoration: BoxDecoration(
                                color: KLPalette.mutedBg,
                                shape: BoxShape.circle,
                                border: Border.all(color: KLPalette.border),
                              ),
                              child: const Icon(Icons.add, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
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

                    // breakdown
                    _LineItem(label: "Package price", value: "RM ${basePrice.toStringAsFixed(2)}"),
                    _LineItem(label: "Included duration", value: fmtHM(includedMinutes)),
                    _LineItem(label: "Selected duration", value: fmtHM(selectedMinutes)),

                    if (extraMinutes > 0)
                      _LineItem(
                        label: extraLabel,
                        value: "RM ${quote.hoursAmount.toStringAsFixed(2)}",
                      ),

                    ...quote.lines.map((l) => _LineItem(
                      label: l.label,
                      value: "${l.amount >= 0 ? '+' : '-'}RM ${l.amount.abs().toStringAsFixed(2)}",
                    )),

                    const Divider(color: KLPalette.border),
                    _LineItem(
                      label: "Estimated total",
                      value: "RM ${quote.total.toStringAsFixed(2)}",
                      bold: true,
                    ),

                    const SizedBox(height: 16),

                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Rules",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (service.pricingRules.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "No pricing rules configured.",
                          style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      Column(
                        children: service.pricingRules.map((r) {
                          final applies = ruleApplies(r, scheduledAt, distanceKm);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RuleCard(rule: r, appliesNow: applies),
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
                    style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.25),
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

    final days = (when["days"] as List?)?.cast<dynamic>().map((e) => (e as num).toInt()).toList();
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
      parts.add("Applies between ${sh.toString().padLeft(2,'0')}:00–${eh.toString().padLeft(2,'0')}:59");
    }

    final minD = (when["minDistanceKm"] as num?)?.toDouble();
    if (minD != null) {
      parts.add("Applies when distance ≥ ${minD.toStringAsFixed(0)} km");
    }

    if (parts.isEmpty) return "Always applies";
    return parts.join(" • ");
  }
}

class _InkCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  const _InkCard({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KLPalette.bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: KLPalette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: KLPalette.tint50,
                  shape: BoxShape.circle,
                  border: Border.all(color: KLPalette.border),
                ),
                child: Icon(icon, color: KLPalette.primary),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              trailing ??
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: KLPalette.text2,
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
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool deleting;

  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
    required this.deleting,
  });

  @override
  Widget build(BuildContext context) {
    Widget circleButton({required IconData icon, required VoidCallback? onTap}) {
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

    return Row(
      children: [
        circleButton(icon: Icons.arrow_back, onTap: onBack),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        const Spacer(),

        Stack(
          alignment: Alignment.center,
          children: [
            circleButton(icon: Icons.delete_outline_rounded, onTap: onDelete),
            if (deleting)
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(width: 10),

        circleButton(icon: Icons.edit_outlined, onTap: onEdit),
      ],
    );
  }
}


class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KLPalette.tint50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18));
  }
}

class _AiSlot {
  final DateTime startAtLocal;
  final double score;
  final double? expectedRevenue;
  final double? expectedBookings;
  final double? expectedViews;
  final double? expectedConversionRate;

  const _AiSlot({
    required this.startAtLocal,
    required this.score,
    this.expectedRevenue,
    this.expectedBookings,
    this.expectedViews,
    this.expectedConversionRate,
  });
}

class ProviderServiceInsightsMini extends StatelessWidget {
  final String providerId;
  final String serviceId;

  const ProviderServiceInsightsMini({
    super.key,
    required this.providerId,
    required this.serviceId,
  });

  static double? _d(dynamic v) => (v is num) ? v.toDouble() : null;

  static List<_AiSlot> _parseAiSlots(List<Map<String, dynamic>> raw) {
    final out = <_AiSlot>[];
    for (final m in raw) {
      final ts = m['startAt'];
      DateTime? dt;
      if (ts is Timestamp) dt = ts.toDate();
      if (ts is DateTime) dt = ts;

      if (dt == null) continue;

      out.add(
        _AiSlot(
          startAtLocal: dt.toLocal(),
          score: _d(m['score']) ?? 0,
          expectedRevenue: _d(m['expectedRevenue']),
          expectedBookings: _d(m['expectedBookings']),
          expectedViews: _d(m['expectedViews']),
          expectedConversionRate: _d(m['expectedConversionRate']),
        ),
      );
    }
    return out;
  }

  static String _wdShort(int wd) {
    switch (wd) {
      case 1: return "Mon";
      case 2: return "Tue";
      case 3: return "Wed";
      case 4: return "Thu";
      case 5: return "Fri";
      case 6: return "Sat";
      case 7: return "Sun";
      default: return "Day";
    }
  }

  static String _fmtHour(int h) => "${h.toString().padLeft(2, '0')}:00";

  static String _fmtShort(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return "$dd/$mm $hh:$mi";
  }

  static bool _isWithinWorkingHoursStrict(DateTime dt, Map<String, dynamic> workingHours) {
    if (workingHours.isEmpty) return true;
    String weekdayKey(DateTime x) {
      switch (x.weekday) {
        case DateTime.monday: return 'mon';
        case DateTime.tuesday: return 'tue';
        case DateTime.wednesday: return 'wed';
        case DateTime.thursday: return 'thu';
        case DateTime.friday: return 'fri';
        case DateTime.saturday: return 'sat';
        case DateTime.sunday:
        default: return 'sun';
      }
    }

    TimeOfDay? parseHHmm(dynamic v) {
      final s = v?.toString();
      if (s == null || !s.contains(':')) return null;
      final parts = s.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return TimeOfDay(hour: h, minute: m);
    }

    int toMin(TimeOfDay t) => t.hour * 60 + t.minute;

    final key = weekdayKey(dt);
    final day = workingHours[key];
    if (day is! Map) return false;
    final m = day.cast<String, dynamic>();

    final enabled = (m['enabled'] == true);
    if (!enabled) return false;

    final start = parseHHmm(m['start']) ?? const TimeOfDay(hour: 9, minute: 0);
    final end = parseHHmm(m['end']) ?? const TimeOfDay(hour: 18, minute: 0);

    final dtMin = dt.hour * 60 + dt.minute;
    final startMin = toMin(start);
    final endMin = toMin(end);

    return dtMin >= startMin && dtMin <= endMin;
  }

  static void _showAiSlotDetails(
      BuildContext context, {
        required _AiSlot s,
        required double serviceAvgPrice,
      }) {
    String rm(double? v) => (v == null) ? "-" : "RM ${v.toStringAsFixed(2)}";
    String num2(double? v) => (v == null) ? "-" : v.toStringAsFixed(2);
    String views0(double? v) => (v == null) ? "-" : v.toStringAsFixed(0);

    // “Service potential revenue” = expectedBookings × serviceAvgPrice
    final eb = s.expectedBookings ?? 0;
    final servicePotential = eb * serviceAvgPrice;

    // Only show conversion when views > 0 (avoids confusing N/A / clipped cases)
    final conv = (s.expectedConversionRate != null &&
        s.expectedViews != null &&
        (s.expectedViews ?? 0) > 0)
        ? "${(s.expectedConversionRate! * 100).toStringAsFixed(2)}%"
        : "N/A";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Slot details",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  "${_wdShort(s.startAtLocal.weekday)} • ${s.startAtLocal.day}/${s.startAtLocal.month}/${s.startAtLocal.year} • ${_fmtHour(s.startAtLocal.hour)}",
                  style: const TextStyle(
                    color: KLPalette.text2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),

                _kv("Service potential (Est.)", "RM ${servicePotential.toStringAsFixed(2)}"),
                _kv("Expected bookings", num2(s.expectedBookings)),
                _kv("Platform expected revenue", rm(s.expectedRevenue)),
                _kv("Expected views", views0(s.expectedViews)),
                _kv("Expected conversion", conv),

                const SizedBox(height: 10),
                const Text(
                  "Note: Service potential is estimated as expected bookings × your service average price.\n"
                      "Platform expected revenue is the model’s overall revenue estimate (may include all services).",
                  style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start28 = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 28));
    final start7 = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));

    final baseQ = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId)
        .where('serviceId', isEqualTo: serviceId);

    final q28 = baseQ
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start28))
        .where('scheduledAt', isLessThanOrEqualTo: Timestamp.fromDate(now));

    final userRef = FirebaseFirestore.instance.collection('users').doc(providerId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: KLPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Insights", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 4),
            const Text(
              "Quick performance (last 28 days)",
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            // --- Status counts + revenue (last 28 days) ---
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q28.snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(minHeight: 3),
                  );
                }

                int pending = 0, accepted = 0, completed = 0, declined = 0;
                double revenueCompleted = 0;

                int last7 = 0;
                for (final d in snap.data!.docs) {
                  final m = d.data();
                  final s = (m['status'] ?? 'pending').toString();

                  if (s == 'pending') pending++;
                  else if (s == 'accepted') accepted++;
                  else if (s == 'completed') {
                    completed++;
                    final amt = m['totalAmount'];
                    if (amt is num) revenueCompleted += amt.toDouble();
                  } else if (s == 'declined') declined++;

                  final ts = m['scheduledAt'];
                  if (ts is Timestamp) {
                    final dt = ts.toDate();
                    if (dt.isAfter(start7)) last7++;
                  }
                }

                final last28 = snap.data!.docs.length;

                final serviceAvgPrice = (completed > 0)
                    ? (revenueCompleted / completed)
                    : 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _MiniStat(label: "Pending", value: pending.toString())),
                        const SizedBox(width: 10),
                        Expanded(child: _MiniStat(label: "Accepted", value: accepted.toString())),
                        const SizedBox(width: 10),
                        Expanded(child: _MiniStat(label: "Completed", value: completed.toString())),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            label: "Declined",
                            value: declined.toString(),
                            bg: KLPalette.tint50,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniStat(
                            label: "Revenue (Completed)",
                            value: "RM ${revenueCompleted.toStringAsFixed(0)}",
                            bg: KLPalette.tint50,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(child: _MiniStat(label: "Last 7 days", value: last7.toString(), bg: KLPalette.tint50)),
                        const SizedBox(width: 10),
                        Expanded(child: _MiniStat(label: "Last 28 days", value: last28.toString(), bg: KLPalette.tint50)),
                      ],
                    ),

                    const SizedBox(height: 14),
                    const Text("AI business prediction (next 7d)", style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),

                    // --- AI slots from users/{uid}.opportunity_index ---
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: userRef.snapshots(),
                      builder: (context, userSnap) {
                        final userData = userSnap.data?.data() ?? const <String, dynamic>{};

                        final workingHoursRaw = (userData['workingHours'] is Map)
                            ? (userData['workingHours'] as Map).cast<String, dynamic>()
                            : <String, dynamic>{};
                        final hasWhFilter = workingHoursRaw.isNotEmpty;

                        final opp = userData['opportunity_index'];
                        final oppMap = (opp is Map) ? Map<String, dynamic>.from(opp as Map) : null;

                        final updatedAtRaw = oppMap?['updatedAt'];
                        final updatedAt = (updatedAtRaw is Timestamp) ? updatedAtRaw : null;

                        final slotsRaw = oppMap?['slots'];
                        final slotsList = (slotsRaw is List)
                            ? slotsRaw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
                            : const <Map<String, dynamic>>[];

                        if (slotsList.isEmpty) {
                          return const Text(
                            "AI forecast not available yet. (Waiting for enough data)",
                            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                          );
                        }

                        final slots = _parseAiSlots(slotsList);

                        // Horizon next 7 days
                        final day0 = DateTime(now.year, now.month, now.day);
                        final dayEnd = day0.add(const Duration(days: 7));

                        final horizon = slots.where((s) {
                          return s.startAtLocal.isAfter(day0.subtract(const Duration(seconds: 1))) &&
                              s.startAtLocal.isBefore(dayEnd);
                        }).toList();

                        if (horizon.isEmpty) {
                          return const Text(
                            "AI forecast exists but no slots in the next 7 days.",
                            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                          );
                        }

                        // Rank by “service potential revenue”
                        double slotPotential(_AiSlot s) =>
                            (s.expectedBookings ?? 0) * (serviceAvgPrice > 0 ? serviceAvgPrice : 1);

                        final inWh = <_AiSlot>[];
                        final outWh = <_AiSlot>[];
                        for (final s in horizon) {
                          if (!hasWhFilter || _isWithinWorkingHoursStrict(s.startAtLocal, workingHoursRaw)) {
                            inWh.add(s);
                          } else {
                            outWh.add(s);
                          }
                        }
                        inWh.sort((a, b) => slotPotential(b).compareTo(slotPotential(a)));
                        outWh.sort((a, b) => slotPotential(b).compareTo(slotPotential(a)));

                        final top = <({ _AiSlot slot, bool outsideWh })>[];
                        for (final s in inWh) {
                          if (top.length >= 3) break;
                          top.add((slot: s, outsideWh: false));
                        }
                        for (final s in outWh) {
                          if (top.length >= 3) break;
                          top.add((slot: s, outsideWh: true));
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (updatedAt != null)
                              Text(
                                "Updated ${_fmtShort(updatedAt.toDate().toLocal())}",
                                style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            if (updatedAt != null) const SizedBox(height: 8),

                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: top.map((item) {
                                final s = item.slot;
                                final outsideWh = item.outsideWh;
                                final label = "${_wdShort(s.startAtLocal.weekday)} ${_fmtHour(s.startAtLocal.hour)}";
                                final avgPrice = (serviceAvgPrice > 0) ? serviceAvgPrice : 0.0;
                                final est = (avgPrice > 0) ? (s.expectedBookings ?? 0) * avgPrice : null;

                                final badge = (est == null)
                                    ? "Score ${s.score.toStringAsFixed(0)}"
                                    : "Est. RM ${est.toStringAsFixed(0)}";

                                const outsideBg = Color(0xFFFFFBEB);
                                const outsideText = Color(0xFFB45309);
                                final bg = outsideWh ? outsideBg : KLPalette.tint50;
                                final timeColor = outsideWh ? outsideText : KLPalette.primary700;
                                final badgeColor = outsideWh ? outsideText : KLPalette.text;

                                return InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => _showAiSlotDetails(
                                    context,
                                    s: s,
                                    serviceAvgPrice: (serviceAvgPrice > 0) ? serviceAvgPrice : 0.0,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: KLPalette.border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(label,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: timeColor,
                                            )),
                                        const SizedBox(width: 8),
                                        Text(badge, style: TextStyle(fontWeight: FontWeight.w900, color: badgeColor,)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 10),
                            const Text(
                              "Tip: Estimates use expected bookings × your service avg completed price (last 28d). Tap a chip for details.",
                              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 12),
                    Container(height: 1, color: KLPalette.border),
                    const SizedBox(height: 10),

                    Row(
                      children: const [
                        Text("View details", style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700)),
                        Spacer(),
                        Icon(Icons.chevron_right_rounded, color: KLPalette.text2),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}


class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? bg;

  const _MiniStat({required this.label, required this.value, this.bg});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: bg ?? KLPalette.bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: KLPalette.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}