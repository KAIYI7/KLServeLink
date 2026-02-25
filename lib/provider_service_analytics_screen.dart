import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'data/provider_services_repo.dart';

enum _RangePreset { d7, d28, d90 }

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

double? _d(dynamic v) => (v is num) ? v.toDouble() : null;

List<_AiSlot> _parseAiSlots(List<Map<String, dynamic>> raw) {
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

String _wdShortX(int wd) {
  switch (wd) {
    case 1:
      return "Mon";
    case 2:
      return "Tue";
    case 3:
      return "Wed";
    case 4:
      return "Thu";
    case 5:
      return "Fri";
    case 6:
      return "Sat";
    case 7:
      return "Sun";
    default:
      return "Day";
  }
}

String _fmtHmX(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return "$hh:$mm";
}

String _fmtShortX(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return "$dd/$mm $hh:$mi";
}

Widget _kvX(String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );
}

void _showAiSlotDetailsSheet(
    BuildContext context, {
      required _AiSlot slot,
      required double serviceAvgPrice,
      Map<String, dynamic>? workingHoursRaw,
    }) {
  String rm(double? v) => (v == null) ? "-" : "RM ${v.toStringAsFixed(2)}";
  String num2(double? v) => (v == null) ? "-" : v.toStringAsFixed(2);
  String views0(double? v) => (v == null) ? "-" : v.toStringAsFixed(0);

  final eb = slot.expectedBookings ?? 0;
  final servicePotential = (serviceAvgPrice > 0) ? eb * serviceAvgPrice : null;

  final views = slot.expectedViews ?? 0;
  final conv = slot.expectedConversionRate;

  final canShowConv = (views > 0 && conv != null);
  final convText = canShowConv ? "${(conv! * 100).toStringAsFixed(2)}%" : "N/A";

  final wh = workingHoursRaw ?? const <String, dynamic>{};
  final bool filteredByWH = wh.isNotEmpty;
  final bool isWithinWH = !filteredByWH
      ? true
      : _WorkingHours.isWithinWorkingHoursStrict(slot.startAtLocal, wh);

  const outsideBg = Color(0xFFFFFBEB);
  const outsideText = Color(0xFFB45309);

  final topReason = _reasonForSlot(slot, serviceAvgPrice);

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

              // Date line + badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      "${_wdShortX(slot.startAtLocal.weekday)} • "
                          "${slot.startAtLocal.day}/${slot.startAtLocal.month}/${slot.startAtLocal.year} • "
                          "${_fmtHmX(slot.startAtLocal)}",
                      style: const TextStyle(
                        color: KLPalette.text2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (filteredByWH && !isWithinWH) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: outsideBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: const Text(
                        "Outside WH",
                        style: TextStyle(fontWeight: FontWeight.w900, color: outsideText, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // Top reason
              Row(
                children: [
                  _badgeX("Top reason"),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      topReason,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Metrics
              _kvX("Opportunity score (0–100)", slot.score.toStringAsFixed(0)),
              _kvX("Expected bookings", num2(slot.expectedBookings)),
              _kvX("Expected views", views0(slot.expectedViews)),
              _kvX("Expected conversion", convText),

              const SizedBox(height: 6),

              _kvX(
                "Est. service revenue",
                servicePotential == null ? "-" : "RM ${servicePotential.toStringAsFixed(2)}",
              ),
              _kvX("Platform expected revenue", rm(slot.expectedRevenue)),

              const SizedBox(height: 12),
              const Text(
                "Note:\n"
                    "• Opportunity score is a relative ranking (0–100) used to compare time slots. Higher = better opportunity.\n"
                    "• Expected bookings = predicted number of bookings for this time slot.\n"
                    "• Expected views = predicted customer views for this time slot.\n"
                    "• Expected conversion = bookings ÷ views (shown only when views > 0).\n"
                    "• Est. service revenue = expected bookings × your service avg completed price.\n"
                    "• Platform expected revenue is the model’s overall revenue estimate (may include all services).",
                style: TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}


class ProviderServiceAnalyticsScreen extends StatefulWidget {
  final ProviderServiceUi service;

  const ProviderServiceAnalyticsScreen({super.key, required this.service});

  @override
  State<ProviderServiceAnalyticsScreen> createState() =>
      _ProviderServiceAnalyticsScreenState();
}

class _ProviderServiceAnalyticsScreenState
    extends State<ProviderServiceAnalyticsScreen> {
  _RangePreset preset = _RangePreset.d28;

  int get _rangeDays {
    switch (preset) {
      case _RangePreset.d7:
        return 7;
      case _RangePreset.d28:
        return 28;
      case _RangePreset.d90:
        return 90;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        backgroundColor: KLPalette.bg,
        body: const SafeArea(child: Center(child: Text("Please login"))),
      );
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            children: [
              _TopBar(
                title: "Service Analytics",
                onBack: () => Navigator.pop(context),
              ),
              const SizedBox(height: 12),

              _RangeToggle(
                value: preset,
                onChanged: (v) => setState(() => preset = v),
              ),
              const SizedBox(height: 14),

              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userRef.snapshots(),
                  builder: (context, userSnap) {
                    final userData = userSnap.data?.data() ?? {};
                    final workingHoursRaw = (userData['workingHours'] is Map)
                        ? (userData['workingHours'] as Map)
                              .cast<String, dynamic>()
                        : <String, dynamic>{};

                    final opp = userData['opportunity_index'];
                    final oppMap = (opp is Map)
                        ? Map<String, dynamic>.from(opp as Map)
                        : null;

                    final updatedAtRaw = oppMap?['updatedAt'];
                    final updatedAt = (updatedAtRaw is Timestamp)
                        ? updatedAtRaw
                        : null;

                    final slotsRaw = oppMap?['slots'];
                    final slotMaps = (slotsRaw is List)
                        ? slotsRaw
                              .whereType<Map>()
                              .map((m) => Map<String, dynamic>.from(m))
                              .toList()
                        : <Map<String, dynamic>>[];

                    final aiSlots = slotMaps.isEmpty
                        ? <_AiSlot>[]
                        : _parseAiSlots(slotMaps);

                    final now = DateTime.now();
                    final start = DateTime(
                      now.year,
                      now.month,
                      now.day,
                    ).subtract(Duration(days: _rangeDays));

                    final q = FirebaseFirestore.instance
                        .collection('bookings')
                        .where('providerId', isEqualTo: uid)
                        .where('serviceId', isEqualTo: widget.service.id)
                        .where(
                          'scheduledAt',
                          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
                        )
                        .where(
                          'scheduledAt',
                          isLessThanOrEqualTo: Timestamp.fromDate(now),
                        );

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      key: ValueKey("${widget.service.id}-${preset.name}"),
                      stream: q.snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        // --- Counters ---
                        int total = 0,
                            pending = 0,
                            accepted = 0,
                            completed = 0,
                            declined = 0;
                        double revenueCompleted = 0;

                        // Trend buckets
                        final bucketDays = (_rangeDays == 7) ? 1 : 7;
                        final bucketCount = (_rangeDays == 7)
                            ? 7
                            : ((_rangeDays / 7).ceil()); // 28=>4, 90=>13
                        final trendCounts = List<int>.filled(bucketCount, 0);
                        final trendRevenue = List<double>.filled(
                          bucketCount,
                          0,
                        );

                        // Peak hours (weekday*100 + hour)
                        final howCounts = <int, int>{};

                        // Top locations
                        final locCounts = <String, int>{};

                        for (final d in snap.data!.docs) {
                          final m = d.data();
                          total++;

                          final status = (m['status'] ?? 'pending').toString();
                          if (status == 'pending')
                            pending++;
                          else if (status == 'accepted')
                            accepted++;
                          else if (status == 'completed')
                            completed++;
                          else if (status == 'declined')
                            declined++;

                          final ts = m['scheduledAt'];
                          DateTime? dt;
                          if (ts is Timestamp) dt = ts.toDate().toLocal();

                          // revenue (completed only)
                          if (status == 'completed') {
                            final amt = m['totalAmount'];
                            if (amt is num) revenueCompleted += amt.toDouble();
                          }

                          // location
                          final areaStored = (m['locationArea'] ?? '')
                              .toString()
                              .trim();
                          final locRaw = (m['locationText'] ?? '')
                              .toString()
                              .trim();

                          final area = areaStored.isNotEmpty
                              ? areaStored
                              : _LocationArea.fromLocationText(locRaw);

                          if (area.isNotEmpty) {
                            locCounts[area] = (locCounts[area] ?? 0) + 1;
                          }

                          if (dt != null) {
                            // Trend bucket
                            final dayFloor = DateTime(
                              dt.year,
                              dt.month,
                              dt.day,
                            );
                            final daysAgo = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            ).difference(dayFloor).inDays;

                            final bucketIndex = (daysAgo ~/ bucketDays);
                            final idx =
                                (bucketCount - 1) -
                                bucketIndex; // oldest->0, newest->last

                            if (idx >= 0 && idx < bucketCount) {
                              trendCounts[idx] += 1;
                              if (status == 'completed') {
                                final amt = m['totalAmount'];
                                if (amt is num)
                                  trendRevenue[idx] += amt.toDouble();
                              }
                            }

                            // Peak hours (FILTER by Working Hours if present)
                            final allow = workingHoursRaw.isEmpty
                                ? true
                                : _WorkingHours.isWithinWorkingHours(
                                    dt,
                                    workingHoursRaw,
                                  );

                            if (allow) {
                              final key = dt.weekday * 100 + dt.hour;
                              howCounts[key] = (howCounts[key] ?? 0) + 1;
                            }
                          }
                        }

                        final completionRate = total == 0
                            ? 0.0
                            : (completed / total);

                        final serviceAvgPrice = (completed > 0)
                            ? (revenueCompleted / completed)
                            : widget.service.price.toDouble();

                        // top locations list
                        final topLoc = locCounts.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));
                        final topLocShow = topLoc.take(5).toList();

                        return ListView(
                          padding: const EdgeInsets.only(bottom: 120),
                          children: [
                            if (aiSlots.isNotEmpty) ...[
                              _AiBusinessPredictionCard(
                                slots: aiSlots,
                                workingHoursRaw: workingHoursRaw,
                                updatedAt: updatedAt,
                                serviceAvgPrice: serviceAvgPrice,
                              ),
                              const SizedBox(height: 12),
                            ],

                            _Card(
                              title: widget.service.name,
                              subtitle:
                                  "${widget.service.category} • Last $_rangeDays days",
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _MiniStat(
                                      label: "Total",
                                      value: total.toString(),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MiniStat(
                                      label: "Completed",
                                      value: completed.toString(),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MiniStat(
                                      label: "Completion",
                                      value:
                                          "${(completionRate * 100).toStringAsFixed(0)}%",
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            _Card(
                              title: "Status",
                              subtitle:
                                  "Provider-focused • Last $_rangeDays days",
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _MiniStat(
                                      label: "Pending",
                                      value: pending.toString(),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MiniStat(
                                      label: "Accepted",
                                      value: accepted.toString(),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MiniStat(
                                      label: "Completed",
                                      value: completed.toString(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            _Card(
                              title: "Revenue (completed)",
                              subtitle: "Last $_rangeDays days",
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.payments_rounded,
                                    color: KLPalette.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    "RM ${revenueCompleted.toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (declined > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: KLPalette.tint50,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: KLPalette.border,
                                        ),
                                      ),
                                      child: Text(
                                        "Declined: $declined",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            _Card(
                              title: (_rangeDays == 7)
                                  ? "Daily trend"
                                  : "Weekly trend",
                              subtitle: (_rangeDays == 7)
                                  ? "Bookings (7 days)"
                                  : "Bookings & revenue (${bucketCount} weeks)",
                              child: Column(
                                children: List.generate(bucketCount, (i) {
                                  final label = (_rangeDays == 7)
                                      ? "Day ${i + 1}"
                                      : "Week ${i + 1}";
                                  final c = trendCounts[i];
                                  final r = trendRevenue[i];

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 70,
                                          child: Text(
                                            label,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: _norm(c, trendCounts),
                                              minHeight: 10,
                                              backgroundColor: KLPalette.tint50,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          "$c",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        if (_rangeDays != 7) ...[
                                          const SizedBox(width: 10),
                                          Text(
                                            "RM ${r.toStringAsFixed(0)}",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 12),

                            _Card(
                              title: "Peak booking hours",
                              subtitle: (aiSlots.isNotEmpty)
                                  ? (workingHoursRaw.isEmpty
                                        ? "AI forecast • Next 7 days"
                                        : "AI forecast (filtered by Working Hours) • Next 7 days")
                                  : (workingHoursRaw.isEmpty
                                        ? "Top slots • Last $_rangeDays days"
                                        : "Filtered by Working Hours • Last $_rangeDays days"),
                              child: (aiSlots.isNotEmpty)
                                  ? _AiPeakHours(
                                      slots: aiSlots,
                                      workingHoursRaw: workingHoursRaw,
                                      serviceAvgPrice: serviceAvgPrice,
                                    )
                                  : _PeakHours(howCounts: howCounts),
                            ),

                            if (topLocShow.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _Card(
                                title: "Top locations",
                                subtitle:
                                    "From bookings • Last $_rangeDays days",
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: topLocShow.map((e) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: KLPalette.tint50,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: KLPalette.border,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            e.key,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: KLPalette.primary700,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "${e.value}",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _norm(int v, List<int> all) {
    if (all.isEmpty) return 0;
    final maxV = all.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return 0;
    return v / maxV;
  }
}

class _RangeToggle extends StatelessWidget {
  final _RangePreset value;
  final ValueChanged<_RangePreset> onChanged;

  const _RangeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _RangePreset v) {
      final selected = v == value;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(v),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? KLPalette.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : KLPalette.text,
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            chip("7D", _RangePreset.d7),
            chip("28D", _RangePreset.d28),
            chip("90D", _RangePreset.d90),
          ],
        ),
      ),
    );
  }
}

class _PeakHours extends StatelessWidget {
  final Map<int, int> howCounts;

  const _PeakHours({required this.howCounts});

  @override
  Widget build(BuildContext context) {
    if (howCounts.isEmpty) {
      return const Text(
        "Not enough data yet for peak hours.",
        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
      );
    }

    final top = howCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final show = top.take(6).toList();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: show.map((e) {
        final wd = e.key ~/ 100;
        final hr = e.key % 100;
        final label = "${_wdShort(wd)} ${hr.toString().padLeft(2, '0')}:00";

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: KLPalette.tint50,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: KLPalette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: KLPalette.primary700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${e.value}",
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static String _wdShort(int wd) {
    switch (wd) {
      case 1:
        return "Mon";
      case 2:
        return "Tue";
      case 3:
        return "Wed";
      case 4:
        return "Thu";
      case 5:
        return "Fri";
      case 6:
        return "Sat";
      case 7:
        return "Sun";
      default:
        return "Day";
    }
  }
}

class _AiPeakHours extends StatelessWidget {
  final List<_AiSlot> slots;
  final Map<String, dynamic> workingHoursRaw;
  final double serviceAvgPrice;

  const _AiPeakHours({
    required this.slots,
    required this.workingHoursRaw,
    required this.serviceAvgPrice,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    final dayEnd = day0.add(const Duration(days: 7));

    final horizonAll = slots.where((s) {
      if (s.startAtLocal.isBefore(day0) || !s.startAtLocal.isBefore(dayEnd)) {
        return false;
      }
      return true;
    }).toList();

    if (horizonAll.isEmpty) {
      return const Text(
          "AI forecast exists but no slots in the next 7 days.",
        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
      );
    }

    double potential(_AiSlot s) =>
        (s.expectedBookings ?? 0) * (serviceAvgPrice > 0 ? serviceAvgPrice : 1);

    final hasWhFilter = workingHoursRaw.isNotEmpty;
    final inWh = <_AiSlot>[];
    final outWh = <_AiSlot>[];
    for (final s in horizonAll) {
      if (!hasWhFilter ||
          _WorkingHours.isWithinWorkingHoursStrict(s.startAtLocal, workingHoursRaw)) {
        inWh.add(s);
      } else {
        outWh.add(s);
      }
    }

    inWh.sort((a, b) => potential(b).compareTo(potential(a)));
    outWh.sort((a, b) => potential(b).compareTo(potential(a)));

    final show = <({ _AiSlot slot, bool outsideWh })>[];
    for (final s in inWh) {
      if (show.length >= 6) break;
      show.add((slot: s, outsideWh: false));
    }
    for (final s in outWh) {
      if (show.length >= 6) break;
      show.add((slot: s, outsideWh: true));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: show.map((item) {
            final s = item.slot;
            final outsideWh = item.outsideWh;
            final wd = s.startAtLocal.weekday;
            final hr = s.startAtLocal.hour;
            final label = "${_wdShort(wd)} ${hr.toString().padLeft(2, '0')}:00";
            final est = (serviceAvgPrice > 0)
                ? (s.expectedBookings ?? 0) * serviceAvgPrice
                : null;

            final badge = (est == null)
                ? "Score ${s.score.toStringAsFixed(0)}"
                : "Est. RM ${est.toStringAsFixed(0)}";

            const outsideBg = Color(0xFFFFFBEB);
            const outsideText = Color(0xFFB45309);
            final bg = outsideWh ? outsideBg : KLPalette.tint50;
            final timeColor = outsideWh ? outsideText : KLPalette.primary700;
            final labelColor = outsideWh ? outsideText : KLPalette.text;

            return InkWell(
              onTap: () => _showAiSlotDetailsSheet(
                context,
                slot: s,
                serviceAvgPrice: serviceAvgPrice,
                workingHoursRaw: workingHoursRaw,
              ),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: KLPalette.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: timeColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      badge,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: labelColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        const Text(
          "Tip: tap a slot to view details.",
          style: TextStyle(
            color: KLPalette.text2,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  static String _wdShort(int wd) {
    switch (wd) {
      case 1:
        return "Mon";
      case 2:
        return "Tue";
      case 3:
        return "Wed";
      case 4:
        return "Thu";
      case 5:
        return "Fri";
      case 6:
        return "Sat";
      case 7:
        return "Sun";
      default:
        return "Day";
    }
  }
}

class _AiBusinessPredictionCard extends StatelessWidget {
  final List<_AiSlot> slots;
  final Map<String, dynamic> workingHoursRaw;
  final Timestamp? updatedAt;
  final double serviceAvgPrice;

  const _AiBusinessPredictionCard({
    required this.slots,
    required this.workingHoursRaw,
    required this.updatedAt,
    required this.serviceAvgPrice,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    final dayEnd = day0.add(const Duration(days: 7));

    final horizonAll = slots.where((s) {
      if (s.startAtLocal.isBefore(day0) || !s.startAtLocal.isBefore(dayEnd)) {
        return false;
      }
      return true;
    }).toList();

    if (horizonAll.isEmpty) {
      return _Card(
        title: "AI business prediction",
        subtitle: "Next 7 days",
        child: const Text(
          "AI forecast not available (or no slots in next 7 days).",
          style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
        ),
      );
    }

    double potential(_AiSlot s) =>
        (s.expectedBookings ?? 0) * (serviceAvgPrice > 0 ? serviceAvgPrice : 1);

    final hasWhFilter = workingHoursRaw.isNotEmpty;
    final inWh = <_AiSlot>[];
    final outWh = <_AiSlot>[];
    for (final s in horizonAll) {
      if (!hasWhFilter ||
          _WorkingHours.isWithinWorkingHoursStrict(s.startAtLocal, workingHoursRaw)) {
        inWh.add(s);
      } else {
        outWh.add(s);
      }
    }
    inWh.sort((a, b) => potential(b).compareTo(potential(a)));
    outWh.sort((a, b) => potential(b).compareTo(potential(a)));

    final top = <({ _AiSlot slot, bool outsideWh })>[];
    for (final s in inWh) {
      if (top.length >= 5) break;
      top.add((slot: s, outsideWh: false));
    }
    for (final s in outWh) {
      if (top.length >= 5) break;
      top.add((slot: s, outsideWh: true));
    }

    final maxV = top.map((e) => potential(e.slot)).fold<double>(0, (p, v) => v > p ? v : p);
    final denom = (maxV <= 0) ? 1.0 : maxV;

    String fmtShort(DateTime d) {
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final hh = d.hour.toString().padLeft(2, '0');
      final mi = d.minute.toString().padLeft(2, '0');
      return "$dd/$mm $hh:$mi";
    }

    return _Card(
      title: "AI business prediction",
      subtitle: updatedAt == null
          ? "Next 7 days • Est. revenue"
          : "Next 7 days • Est. revenue • Updated ${fmtShort(updatedAt!.toDate().toLocal())}",
      child: Column(
        children: top.map((item) {
          final s = item.slot;
          final outsideWh = item.outsideWh;
          final label =
              "${_AiPeakHours._wdShort(s.startAtLocal.weekday)} ${s.startAtLocal.hour.toString().padLeft(2, '0')}:00";
          final est = potential(s);
          final double bar = (est / denom).clamp(0.0, 1.0).toDouble();

          const outsideBg = Color(0xFFFFFBEB);
          const outsideText = Color(0xFFB45309);
          final bg = outsideWh ? outsideBg : Colors.transparent;
          final labelColor = outsideWh ? outsideText : KLPalette.text;
          final amtColor = outsideWh ? outsideText : KLPalette.text;
          final barBg = outsideWh ? outsideBg : KLPalette.tint50;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => _showAiSlotDetailsSheet(
                context,
                slot: s,
                serviceAvgPrice: serviceAvgPrice,
                workingHoursRaw: workingHoursRaw,
              ),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: outsideWh ? Border.all(color: KLPalette.border) : null,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: labelColor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: bar.isNaN ? 0 : bar,
                          minHeight: 10,
                          backgroundColor: barBg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "RM ${est.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: amtColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WorkingHours {
  static String _weekdayKey(DateTime dt) {
    switch (dt.weekday) {
      case DateTime.monday:
        return 'mon';
      case DateTime.tuesday:
        return 'tue';
      case DateTime.wednesday:
        return 'wed';
      case DateTime.thursday:
        return 'thu';
      case DateTime.friday:
        return 'fri';
      case DateTime.saturday:
        return 'sat';
      case DateTime.sunday:
      default:
        return 'sun';
    }
  }

  static TimeOfDay? _parseHHmm(dynamic v) {
    final s = v?.toString();
    if (s == null || !s.contains(':')) return null;
    final parts = s.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static int _toMin(TimeOfDay t) => t.hour * 60 + t.minute;

  static bool isWithinWorkingHours(
    DateTime dt,
    Map<String, dynamic> workingHours,
  ) {
    final key = _weekdayKey(dt);
    final day = workingHours[key];
    if (day is! Map) return true; // malformed -> do not block
    final m = day.cast<String, dynamic>();

    final enabled = (m['enabled'] ?? false) as bool;
    if (!enabled) return false;

    final start = _parseHHmm(m['start']) ?? const TimeOfDay(hour: 9, minute: 0);
    final end = _parseHHmm(m['end']) ?? const TimeOfDay(hour: 18, minute: 0);

    final dtMin = dt.hour * 60 + dt.minute;
    final startMin = _toMin(start);
    final endMin = _toMin(end);

    return dtMin >= startMin && dtMin <= endMin;
  }

  static bool isWithinWorkingHoursStrict(
    DateTime dt,
    Map<String, dynamic> workingHours,
  ) {
    if (workingHours.isEmpty) return true;

    final key = _weekdayKey(dt);
    final day = workingHours[key];
    if (day is! Map) return false; // missing => closed

    final m = day.cast<String, dynamic>();
    final enabled = (m['enabled'] == true);
    if (!enabled) return false;

    final start = _parseHHmm(m['start']) ?? const TimeOfDay(hour: 9, minute: 0);
    final end = _parseHHmm(m['end']) ?? const TimeOfDay(hour: 18, minute: 0);

    final dtMin = dt.hour * 60 + dt.minute;
    final startMin = _toMin(start);
    final endMin = _toMin(end);

    return dtMin >= startMin && dtMin <= endMin;
  }
}

class _LocationArea {
  static const _knownAreas = <String>{
    "ampang",
    "bangsar",
    "bangsar south",
    "bandar tun razak",
    "bandar tasik selatan",
    "brickfields",
    "bukit bintang",
    "bukit jalil",
    "bukit tunku",
    "cheras",
    "chow kit",
    "city centre",
    "damansara",
    "damansara heights",
    "danau kota",
    "desa petaling",
    "desa setapak",
    "desa sri hartamas",
    "desapark city",
    "gombak",
    "jalan ipoh",
    "jalan klang lama",
    "jinjang",
    "kampung baru",
    "kepong",
    "keramat",
    "klcc",
    "kl sentral",
    "kuchai lama",
    "lembah pantai",
    "maluri",
    "manjalara",
    "medan tuanku",
    "mid valley",
    "mont kiara",
    "old klang road",
    "oug",
    "pantai dalam",
    "petaling street",
    "pudu",
    "salak south",
    "segambut",
    "sentul",
    "seputeh",
    "setapak",
    "setiawangsa",
    "shamelin",
    "solaris dutamas",
    "sri petaling",
    "sri rampai",
    "sungai besi",
    "taman connaught",
    "taman desa",
    "taman melati",
    "taman tun dr ismail",
    "ttdi",
    "titiwangsa",
    "wangsa maju",
  };

  static String fromLocationText(String s) {
    if (s.trim().isEmpty) return "";

    // Normalize
    final raw = s.replaceAll(RegExp(r"\s+"), " ").trim();

    // Split by comma segments (most addresses are comma-separated)
    final parts = raw
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return "";

    final detected = _detectKnownArea(parts);
    if (detected.isNotEmpty) return detected;

    // Common “city/state/country” tails which don't want as "area"
    const stopWords = {
      "kuala lumpur",
      "wilayah persekutuan",
      "selangor",
      "malaysia",
    };

    bool isPostcode(String x) => RegExp(r"^\d{5}$").hasMatch(x);
    bool looksLikeCityLine(String x) {
      final xl = x.toLowerCase();
      if (stopWords.contains(xl)) return true;
      // "53300 Kuala Lumpur" style
      if (RegExp(r"^\d{5}\s+").hasMatch(xl)) return true;
      return false;
    }

    // Walk from the end, skipping postcode/city/state/country
    int i = parts.length - 1;

    // Skip trailing city/state/country chunks
    while (i >= 0 && looksLikeCityLine(parts[i])) {
      i--;
    }

    // If land on a pure postcode, skip it too
    if (i >= 0 && isPostcode(parts[i])) {
      i--;
    }

    // Pick a likely “area” candidate:
    // Prefer the nearest remaining token from the tail (often the neighborhood)
    while (i >= 0) {
      final cand = parts[i].trim();
      final cl = cand.toLowerCase();

      // Skip empty/stopwords again
      if (cand.isEmpty ||
          stopWords.contains(cl) ||
          looksLikeCityLine(cand) ||
          isPostcode(cand)) {
        i--;
        continue;
      }

      // Avoid lines that are clearly unit/building/road
      final isRoadLike = RegExp(
        r"\b(jalan|lorong|persiaran|lebuh|road|rd|street|st|avenue|ave)\b",
        caseSensitive: false,
      ).hasMatch(cand);
      final isUnitLike = RegExp(
        r"\b(no\.?|unit|block|blok|b-\d+|\d+[a-z]?)\b",
        caseSensitive: false,
      ).hasMatch(cand);

      // If it's road/unit-like, keep walking upwards to find a better area token
      if (isRoadLike || isUnitLike) {
        i--;
        continue;
      }

      return _titleCase(cand);
    }

    // Fallback: if can't confidently parse, use city if present
    final city = parts.firstWhere(
      (p) => p.toLowerCase().contains("kuala lumpur"),
      orElse: () => "",
    );
    if (city.isNotEmpty) return "Kuala Lumpur";

    // Last fallback: use last part trimmed
    return _titleCase(parts.last);
  }

  static String _titleCase(String s) {
    final words = s.split(" ").where((w) => w.isNotEmpty).toList();
    return words
        .map((w) {
          if (w.length <= 1) return w.toUpperCase();
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        })
        .join(" ");
  }

  static String _detectKnownArea(List<String> parts) {
    final full = parts.join(", ").toLowerCase();

    final sorted = _knownAreas.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final a in sorted) {
      final pattern = RegExp(r'(^|[^a-z])' + RegExp.escape(a) + r'([^a-z]|$)');
      if (pattern.hasMatch(full)) {
        return _titleCase(a);
      }
    }

    return "";
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
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _Card({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
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
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: KLPalette.text2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: KLPalette.tint50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: KLPalette.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: KLPalette.text2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _reasonForSlot(_AiSlot s, double serviceAvgPrice) {
  final eb = s.expectedBookings ?? 0;
  final estRevenue = (serviceAvgPrice > 0) ? eb * serviceAvgPrice : 0;
  final views = s.expectedViews ?? 0;
  final conv = s.expectedConversionRate ?? 0;

  // Prioritize the most suitable reasons
  if (estRevenue > 0) return "High revenue potential";
  if (eb > 0) return "High bookings forecast";
  if (views > 0 && conv > 0) return "Strong demand & conversion";
  if (views > 0) return "High demand forecast";
  return "High overall opportunity";
}

Widget _badgeX(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: KLPalette.tint50,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: KLPalette.border),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        color: KLPalette.primary700,
        fontSize: 12,
      ),
    ),
  );
}
