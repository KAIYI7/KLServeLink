import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../dashboard/screens/provider_dashboard_tab.dart'
    show ProviderHighOpportunityScreen;

class ProviderInsightsTab extends StatelessWidget {
  const ProviderInsightsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: const [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _CircleBrand(),
                    ),
                    Center(
                      child: Text(
                        "Insights",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(width: 48, height: 48),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: (uid == null)
                    ? const Center(child: Text("Please login"))
                    : ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    _HighOpportunityCard(providerId: uid),
                    const SizedBox(height: 12),
                    _RevenueTrendCard(providerId: uid),
                    const SizedBox(height: 12),
                    _RevenueSummaryCard(providerId: uid),
                    const SizedBox(height: 12),
                    _ReviewThemesCard(providerId: uid),
                    const SizedBox(height: 12),
                    _BookingSummaryCard(providerId: uid),
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

/// ---------------------------------------------------------------------------
/// High-Opportunity Hours
/// ---------------------------------------------------------------------------

class _HighOpportunityCard extends StatelessWidget {
  final String providerId;
  const _HighOpportunityCard({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final historyEnd =
    DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final historyStart = historyEnd.subtract(const Duration(days: 28));

    final aiStart = DateTime(now.year, now.month, now.day);
    final aiEnd = aiStart.add(const Duration(days: 7));

    final bookingsQ = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId)
        .where('scheduledAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(historyStart))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(historyEnd));

    final userRef = FirebaseFirestore.instance.collection('users').doc(providerId);
    final workingHoursDoc =
    FirebaseFirestore.instance.collection('users').doc(providerId);

    void openDrilldown() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProviderHighOpportunityScreen(providerId: providerId),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return _TappableCard(
            onTap: openDrilldown,
            child: _Card(
              title: "High-Opportunity Hours",
              subtitle: "Next 7 days",
              headerTrailing: InkWell(
                onTap: () => _showHighOppInfo(context),
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.info_outline,
                      color: KLPalette.text2, size: 20),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            ),
          );
        }

        final userData = userSnap.data!.data() ?? const <String, dynamic>{};

        final opp = userData['opportunity_index'];
        final oppMap =
        (opp is Map) ? Map<String, dynamic>.from(opp as Map) : null;

        final updatedAtRaw = oppMap?['updatedAt'];
        final updatedAt = (updatedAtRaw is Timestamp) ? updatedAtRaw : null;

        final slotsRaw = oppMap?['slots'];
        final slots = (slotsRaw is List)
            ? slotsRaw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
            : <Map<String, dynamic>>[];

        final whFallback = (userData['workingHours'] is Map)
            ? (userData['workingHours'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: workingHoursDoc.snapshots(),
          builder: (context, whSnap) {
            final hasWhDoc = whSnap.data?.exists == true &&
                (whSnap.data?.data()?.isNotEmpty ?? false);

            Map<String, dynamic> workingHoursRaw = whFallback;

            if (hasWhDoc) {
              final data = Map<String, dynamic>.from(whSnap.data!.data()!);
              workingHoursRaw =
              Map<String, dynamic>.from(data['workingHours'] ?? {});
            }

            if (slots.isNotEmpty) {
              final subtitle = updatedAt == null
                  ? "Next 7 days • AI forecast"
                  : "Next 7 days • AI forecast • Updated ${_fmtShort(updatedAt.toDate().toLocal())}";

              return _TappableCard(
                onTap: openDrilldown,
                child: _Card(
                  title: "High-Opportunity Hours",
                  subtitle: subtitle,
                  headerTrailing: InkWell(
                    onTap: () => _showHighOppInfo(context),
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.info_outline,
                          color: KLPalette.text2, size: 20),
                    ),
                  ),
                  child: Column(
                    children: [
                      _AiOppSummaryList(
                        slotsRaw: slots,
                        workingHoursRaw: workingHoursRaw,
                        start: aiStart,
                        end: aiEnd,
                      ),
                      const SizedBox(height: 10),
                      const _ViewDetailsRow(),
                    ],
                  ),
                ),
              );
            }

            return _TappableCard(
              onTap: openDrilldown,
              child: _Card(
                title: "High-Opportunity Hours",
                subtitle: "Next 7 days (heuristic)",
                headerTrailing: InkWell(
                  onTap: () => _showHighOppInfo(context),
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.info_outline,
                        color: KLPalette.text2, size: 20),
                  ),
                ),
                child: Column(
                  children: [
                    _HeuristicOppBars(
                      bookingsQ: bookingsQ,
                      horizonStart: aiStart,
                      workingHoursRaw: workingHoursRaw,
                    ),
                    const SizedBox(height: 10),
                    const _ViewDetailsRow(),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _fmtShort(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return "$dd/$mm $hh:$mi";
  }

  void _showHighOppInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  "About High-Opportunity Hours",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                SizedBox(height: 10),
                Text(
                  "This card highlights the best hours to be available in the next 7 days.\n\n"
                      "What each element means:\n"
                      "• Bar: A relative indicator (0–100%) showing how strong this hour is compared to the other shown hours. "
                      "It is scaled to the top suggested hour.\n\n"
                      "• Est. RM: Predicted revenue for that hour (planning estimate). "
                      "This is an overall forecast signal from the platform model.\n\n"
                      "• Conversion: Predicted conversion rate (bookings ÷ views). "
                      "Shown as a percentage when available.\n\n"
                      "• Views: Predicted number of customer views during that hour.\n\n"
                      "Working Hours awareness:\n"
                      "• Normal (primary color) rows are within your Working Hours.\n"
                      "• Highlighted (amber) rows are strong opportunities outside your Working Hours — consider expanding availability to capture them.\n\n"
                      "AI vs heuristic mode:\n"
                      "• If AI forecast exists, the list is based on the platform opportunity_index slots.\n"
                      "• If not, the fallback uses your past booking history to estimate strong hours.\n\n"
                      "How this differs from the AI prediction inside a service detail screen:\n"
                      "• This Insights tab is provider-level (overall demand/opportunity).\n"
                      "• Service detail AI prediction is service-level and often estimates potential using "
                      "that service’s own completed average price and expected bookings.",
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
      },
    );
  }
}

class _TappableCard extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TappableCard({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class _ViewDetailsRow extends StatelessWidget {
  const _ViewDetailsRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text(
          "View details",
          style: TextStyle(
            color: KLPalette.text2,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        Spacer(),
        Icon(Icons.arrow_forward_rounded, size: 18, color: KLPalette.text2),
      ],
    );
  }
}

class _AiOppSummaryList extends StatelessWidget {
  final List<Map<String, dynamic>> slotsRaw;
  final Map<String, dynamic> workingHoursRaw;
  final DateTime start;
  final DateTime end;

  const _AiOppSummaryList({
    required this.slotsRaw,
    required this.workingHoursRaw,
    required this.start,
    required this.end,
  });

  double? _d(dynamic v) => (v is num) ? v.toDouble() : null;

  @override
  Widget build(BuildContext context) {
    const outsideColor = Color(0xFFF59E0B);
    final insideColor = KLPalette.primary;

    final slots =
    <({DateTime dt, double score, double? rev, double? bk, double? views, double? conv, bool inWh})>[];

    for (final m in slotsRaw) {
      final ts = m['startAt'];
      DateTime? dt;
      if (ts is Timestamp) dt = ts.toDate();
      if (ts is DateTime) dt = ts;

      final score = _d(m['score']) ?? 0;
      final rev = _d(m['expectedRevenue']);
      final bk = _d(m['expectedBookings']);
      final views = _d(m['expectedViews']);
      final conv = _d(m['expectedConversionRate']);

      if (dt == null) continue;
      final local = dt.toLocal();

      if (local.isBefore(start) || !local.isBefore(end)) continue;

      final bool inWh = workingHoursRaw.isEmpty
          ? true
          : _HeuristicOppBars._isWithinWorkingHoursStrict(local, workingHoursRaw);

      slots.add((
      dt: local,
      score: score,
      rev: rev,
      bk: bk,
      views: views,
      conv: conv,
      inWh: inWh
      ));
    }

    if (slots.isEmpty) {
      return const Text(
        "AI forecast exists but no suggested slots in the next 7 days.",
        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
      );
    }

    double metric(double? rev, double score) => (rev ?? score);

    int cmp(a, b) {
      final av = metric(a.rev, a.score);
      final bv = metric(b.rev, b.score);
      if (av != bv) return bv.compareTo(av);
      return b.score.compareTo(a.score);
    }

    final inWhSlots = slots.where((s) => s.inWh).toList()..sort(cmp);
    final outWhSlots = slots.where((s) => !s.inWh).toList()..sort(cmp);

    final top =
    <({DateTime dt, double score, double? rev, double? bk, double? views, double? conv, bool inWh})>[];
    top.addAll(inWhSlots.take(5));
    if (top.length < 5) {
      top.addAll(outWhSlots.take(5 - top.length));
    }

    final maxBar = top
        .map((e) => metric(e.rev, e.score))
        .fold<double>(0, (p, v) => (v > p) ? v : p);
    final denom = (maxBar <= 0) ? 1.0 : maxBar;

    final hasOutShown = top.any((e) => !e.inWh);

    return Column(
      children: [
        ...top.map((e) {
          final dt = e.dt;
          final label =
              "${_wdShort(dt.weekday)} ${dt.hour.toString().padLeft(2, '0')}:00";

          final barVal = metric(e.rev, e.score) / denom;
          final barColor = e.inWh ? insideColor : outsideColor;

          final revText =
          (e.rev == null) ? "-" : "Est. RM ${e.rev!.toStringAsFixed(0)}";
          final convText =
          (e.conv == null) ? null : "${(e.conv! * 100).toStringAsFixed(1)}%";
          final viewsText =
          (e.views == null) ? null : "${e.views!.toStringAsFixed(0)} views";
          final whText = e.inWh ? null : "Outside WH";

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: barVal.isNaN ? 0 : barVal.clamp(0, 1),
                      minHeight: 10,
                      backgroundColor: KLPalette.tint50,
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      revText,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: e.inWh ? KLPalette.text : outsideColor,
                      ),
                    ),
                    if (whText != null || convText != null || viewsText != null)
                      Text(
                        [whText, convText, viewsText]
                            .whereType<String>()
                            .join(" • "),
                        style: TextStyle(
                          fontSize: 11,
                          color: e.inWh ? KLPalette.text2 : outsideColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
        if (hasOutShown) ...[
          const SizedBox(height: 6),
          const Text(
            "Highlighted rows are strong opportunities outside your Working Hours. Consider expanding availability to capture them.",
            style: TextStyle(
              color: KLPalette.text2,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
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

class _HeuristicOppBars extends StatelessWidget {
  final Query<Map<String, dynamic>> bookingsQ;
  final DateTime horizonStart;
  final Map<String, dynamic> workingHoursRaw;

  const _HeuristicOppBars({
    required this.bookingsQ,
    required this.horizonStart,
    required this.workingHoursRaw,
  });

  @override
  Widget build(BuildContext context) {
    final hasWorkingHours = workingHoursRaw.isNotEmpty;

    final allowedHours = List<bool>.filled(24, true);
    if (hasWorkingHours) {
      for (var i = 0; i < 24; i++) {
        allowedHours[i] = false;
      }
      for (int i = 0; i < 7; i++) {
        final day = horizonStart.add(Duration(days: i));
        _markAllowedHoursForDay(
          allowedHours: allowedHours,
          date: day,
          workingHours: workingHoursRaw,
        );
      }
    }

    if (hasWorkingHours && allowedHours.every((v) => v == false)) {
      return const Text(
        "You’re not available in the next 7 days (Working Hours is closed).",
        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: bookingsQ.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(minHeight: 3),
          );
        }

        final counts = List<int>.filled(24, 0);

        for (final d in snap.data!.docs) {
          final ts = d.data()['scheduledAt'];
          if (ts is! Timestamp) continue;

          final dt = ts.toDate().toLocal();

          if (hasWorkingHours) {
            final ok = _isWithinWorkingHoursStrict(dt, workingHoursRaw);
            if (!ok) continue;
          }

          counts[dt.hour] += 1;
        }

        final pairs = <MapEntry<int, int>>[];
        for (int h = 0; h < 24; h++) {
          if (hasWorkingHours && !allowedHours[h]) continue;
          pairs.add(MapEntry(h, counts[h]));
        }

        pairs.sort((a, b) => b.value.compareTo(a.value));
        final top = pairs.take(5).toList();

        if (top.isEmpty || top.every((e) => e.value == 0)) {
          return Text(
            hasWorkingHours
                ? "Not enough data yet within your Working Hours. Complete more bookings to generate insights."
                : "Not enough data yet. Complete more bookings to generate insights.",
            style: const TextStyle(
                color: KLPalette.text2, fontWeight: FontWeight.w700),
          );
        }

        final maxV = top.first.value == 0 ? 1 : top.first.value;

        return Column(
          children: top.map((e) {
            final h = e.key;
            final v = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      _fmtHour(h),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: v == 0 ? 0 : (v / maxV),
                        minHeight: 10,
                        backgroundColor: KLPalette.tint50,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "$v",
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  static String _fmtHour(int h) => "${h.toString().padLeft(2, '0')}:00";

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

  static bool _isWithinWorkingHoursStrict(
      DateTime dt, Map<String, dynamic> workingHours) {
    if (workingHours.isEmpty) return true;

    final key = _weekdayKey(dt);
    final day = workingHours[key];
    if (day is! Map) return false;

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

  static void _markAllowedHoursForDay({
    required List<bool> allowedHours,
    required DateTime date,
    required Map<String, dynamic> workingHours,
  }) {
    if (workingHours.isEmpty) return;

    final key = _weekdayKey(date);
    final day = workingHours[key];
    if (day is! Map) return;

    final m = day.cast<String, dynamic>();
    final enabled = (m['enabled'] == true);
    if (!enabled) return;

    final start = _parseHHmm(m['start']) ?? const TimeOfDay(hour: 9, minute: 0);
    final end = _parseHHmm(m['end']) ?? const TimeOfDay(hour: 18, minute: 0);

    final startMin = _toMin(start);
    final endMin = _toMin(end);

    for (int h = 0; h < 24; h++) {
      final hourStart = h * 60;
      final hourEnd = h * 60 + 59;
      final intersects = !(hourEnd < startMin || hourStart > endMin);
      if (intersects) allowedHours[h] = true;
    }
  }
}

/// ---------------------------------------------------------------------------
/// Revenue Trend
/// ---------------------------------------------------------------------------

class _RevenueTrendCard extends StatelessWidget {
  final String providerId;
  const _RevenueTrendCard({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 7, 1);
    final end = DateTime(now.year, now.month + 1, 1);

    final q = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end));

    void showDetails(List<DateTime> months, List<double> totals) {
      _RevenueTrendDetailsSheet.show(context, months: months, totals: totals);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _Card(
            title: "Revenue Trend",
            subtitle: "Last 8 months • completed jobs",
            headerTrailing: InkWell(
              onTap: () => _showRevenueInfo(context),
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.info_outline,
                    color: KLPalette.text2, size: 20),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          );
        }

        final months = List.generate(
          8,
              (i) => DateTime(now.year, now.month - 7 + i, 1),
        );
        final totals = List<double>.filled(8, 0);

        for (final d in snap.data!.docs) {
          final m = d.data();
          if (!_isCompletedBooking(m)) continue;

          final dt = _toDateTime(m['scheduledAt']);
          if (dt == null) continue;

          final idx = _monthIndex(months, dt);
          if (idx == null) continue;

          totals[idx] += _bookingAmountForProvider(m);
        }

        final maxV = totals.fold<double>(0, (p, v) => math.max(p, v));
        final fractions = totals
            .map((v) => (maxV <= 0) ? 0.0 : (v / maxV).clamp(0.0, 1.0))
            .toList();
        final labels = months.map(_monLabel).toList();
        final total8 = totals.fold<double>(0, (p, v) => p + v);

        return _TappableCard(
          onTap: () => showDetails(months, totals),
          child: _Card(
            title: "Revenue Trend",
            subtitle: "Last 8 months • completed jobs",
            headerTrailing: InkWell(
              onTap: () => _showRevenueInfo(context),
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.info_outline,
                    color: KLPalette.text2, size: 20),
              ),
            ),
            child: Column(
              children: [
                _RevenueBarPreview(
                  labels: labels,
                  fractions: fractions,
                  caption:
                  "Total ${_fmtRmCompact(total8)} • Tap to view breakdown",
                ),
                const SizedBox(height: 10),
                const _ViewDetailsRow(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRevenueInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "About Revenue Trend",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                SizedBox(height: 10),
                Text(
                  "This trend shows provider-side earnings across the last 8 months.\n\n"
                      "Rules used:\n"
                      "• Only completed bookings are counted in the monthly trend.\n"
                      "• Amount prefers provider-specific payout/net fields when available.\n"
                      "• If those fields are missing, it falls back to booking total fields.\n"
                      "• Grouping is based on the booking scheduled month.\n\n"
                      "Use this card to see whether your income is trending up or down over time.",
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
      },
    );
  }
}

class _RevenueBarPreview extends StatelessWidget {
  final List<String> labels;
  final List<double> fractions;
  final String caption;

  const _RevenueBarPreview({
    required this.labels,
    required this.fractions,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(labels.length, (i) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 120 * fractions[i],
                      decoration: BoxDecoration(
                        color: KLPalette.primary.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: KLPalette.border),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[i],
                      style: const TextStyle(
                        color: KLPalette.text2,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            caption,
            style: const TextStyle(
              color: KLPalette.text2,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _RevenueTrendDetailsSheet extends StatelessWidget {
  final List<DateTime> months;
  final List<double> totals;

  const _RevenueTrendDetailsSheet({
    required this.months,
    required this.totals,
  });

  static void show(
      BuildContext context, {
        required List<DateTime> months,
        required List<double> totals,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _RevenueTrendDetailsSheet(months: months, totals: totals),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = totals.fold<double>(0, (p, v) => p + v);
    final avg = totals.isEmpty ? 0.0 : total / totals.length;

    int bestIdx = 0;
    double bestVal = -1;
    for (int i = 0; i < totals.length; i++) {
      if (totals[i] > bestVal) {
        bestVal = totals[i];
        bestIdx = i;
      }
    }

    final last = totals.isNotEmpty ? totals.last : 0.0;
    final prev = totals.length >= 2 ? totals[totals.length - 2] : 0.0;
    final mom = (prev > 0) ? ((last - prev) / prev) : null;

    String monYear(DateTime d) => "${_monLabel(d)} ${d.year}";

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Revenue Trend",
                      style:
                      TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniKpiCard(
                      label: "Total",
                      value: _fmtRmCompact(total),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniKpiCard(
                      label: "Avg / month",
                      value: _fmtRmCompact(avg),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniKpiCard(
                      label: "Best month",
                      value:
                      "${_monLabel(months[bestIdx])} • ${_fmtRmCompact(bestVal)}",
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniKpiCard(
                      label: "MoM (latest)",
                      value: (mom == null)
                          ? "N/A"
                          : "${(mom * 100).toStringAsFixed(1)}%",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _RevenueLineChart(
                labels: months.map(_monLabel).toList(),
                values: totals,
              ),
              const SizedBox(height: 12),
              const Text(
                "What this means",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                "• Revenue shown is based on completed bookings only.\n"
                    "• Grouped by booking scheduled month (local time).\n"
                    "• Amount prefers provider payout/net fields, then falls back to booking totals.",
                style: TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Breakdown",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              ...List.generate(months.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          monYear(months[i]),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        _fmtRmCompact(totals[i]),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniKpiCard extends StatelessWidget {
  final String label;
  final String value;

  const _MiniKpiCard({required this.label, required this.value});

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
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
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

class _RevenueLineChart extends StatefulWidget {
  final List<String> labels;
  final List<double> values;

  const _RevenueLineChart({
    required this.labels,
    required this.values,
  });

  @override
  State<_RevenueLineChart> createState() => _RevenueLineChartState();
}

class _RevenueLineChartState extends State<_RevenueLineChart> {
  int? _selectedIndex;
  Timer? _hideTimer;

  static const Duration _tooltipHold = Duration(seconds: 2);
  static const double _leftPad = 8;
  static const double _rightPad = 8;
  static const double _topPad = 10;
  static const double _bottomPad = 26;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_tooltipHold, () {
      if (!mounted) return;
      setState(() => _selectedIndex = null);
    });
  }

  void _handleTouch(Offset localPos, Size size, {required bool toggle}) {
    final n = widget.values.length;
    if (n <= 0) return;

    final w = size.width - _leftPad - _rightPad;
    final h = size.height - _topPad - _bottomPad;
    if (w <= 0 || h <= 0) return;

    final dx = (localPos.dx - _leftPad).clamp(0.0, w);
    final t = (n == 1) ? 0.0 : (dx / w);
    final idx = (t * (n - 1)).round().clamp(0, n - 1);

    _hideTimer?.cancel();

    if (toggle) {
      setState(() {
        _selectedIndex = (_selectedIndex == idx) ? null : idx;
      });
    } else {
      if (_selectedIndex == idx) return;
      setState(() {
        _selectedIndex = idx;
      });
    }
  }

  Offset _pointFor(int i, Size size) {
    final n = widget.values.length;
    final w = size.width - _leftPad - _rightPad;
    final h = size.height - _topPad - _bottomPad;

    final maxV = widget.values.fold<double>(0, (p, v) => math.max(p, v));
    final safeMax = maxV <= 0 ? 1.0 : maxV;

    double xAt(int idx) {
      if (n == 1) return _leftPad + w / 2;
      return _leftPad + (w * (idx / (n - 1)));
    }

    double yAt(double v) {
      final t = (v / safeMax).clamp(0.0, 1.0);
      return _topPad + (h * (1 - t));
    }

    return Offset(xAt(i), yAt(widget.values[i]));
  }

  Widget _tooltip(Size size) {
    final idx = _selectedIndex;
    if (idx == null) return const SizedBox.shrink();

    final p = _pointFor(idx, size);
    final label = (idx < widget.labels.length) ? widget.labels[idx] : "";
    final value = _fmtRmCompact(widget.values[idx]);

    const tooltipW = 170.0;
    const tooltipH = 54.0;
    const pad = 8.0;

    final left = math.min(
      math.max(p.dx - tooltipW / 2, pad),
      size.width - tooltipW - pad,
    );
    final top = math.min(
      math.max(p.dy - tooltipH - 10, pad),
      size.height - tooltipH - pad,
    );

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: tooltipW,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KLPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: KLPalette.text2,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final size = Size(c.maxWidth, c.maxHeight);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _handleTouch(d.localPosition, size, toggle: true),
              onTapUp: (_) => _scheduleHide(),
              onPanDown: (d) =>
                  _handleTouch(d.localPosition, size, toggle: false),
              onPanUpdate: (d) =>
                  _handleTouch(d.localPosition, size, toggle: false),
              onPanEnd: (_) => _scheduleHide(),
              child: Stack(
                children: [
                  CustomPaint(
                    painter: _RevenueLineChartPainter(
                      labels: widget.labels,
                      values: widget.values,
                      selectedIndex: _selectedIndex,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  _tooltip(size),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RevenueLineChartPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final int? selectedIndex;

  _RevenueLineChartPainter({
    required this.labels,
    required this.values,
    required this.selectedIndex,
  });

  static const double leftPad = 8;
  static const double rightPad = 8;
  static const double topPad = 10;
  static const double bottomPad = 26;

  double _clampTextX(double x, double textWidth, double canvasW) {
    if (canvasW <= textWidth) return 0;
    return x.clamp(0.0, canvasW - textWidth);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;

    final w = size.width - leftPad - rightPad;
    final h = size.height - topPad - bottomPad;
    if (w <= 0 || h <= 0) return;

    final maxV = values.fold<double>(0, (p, v) => math.max(p, v));
    final safeMax = maxV <= 0 ? 1.0 : maxV;

    double xAt(int i) {
      if (n == 1) return leftPad + w / 2;
      return leftPad + (w * (i / (n - 1)));
    }

    double yAt(double v) {
      final t = (v / safeMax).clamp(0.0, 1.0);
      return topPad + (h * (1 - t));
    }

    final gridPaint = Paint()
      ..color = KLPalette.border
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(leftPad, topPad + h),
      Offset(leftPad + w, topPad + h),
      gridPaint,
    );

    for (final frac in const [0.25, 0.5, 0.75]) {
      final y = topPad + h * (1 - frac);
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + w, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = KLPalette.primary700
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < n; i++) {
      final p = Offset(xAt(i), yAt(values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < n) {
      final p = Offset(xAt(selectedIndex!), yAt(values[selectedIndex!]));
      final crossPaint = Paint()
        ..color = KLPalette.primary700.withOpacity(0.18)
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(p.dx, topPad),
        Offset(p.dx, topPad + h),
        crossPaint,
      );
    }

    final dotPaint = Paint()..color = KLPalette.primary700;

    for (int i = 0; i < n; i++) {
      final p = Offset(xAt(i), yAt(values[i]));
      final isSel = (i == selectedIndex);

      canvas.drawCircle(p, isSel ? 5.2 : 3.2, dotPaint);

      if (isSel) {
        final ring = Paint()
          ..color = KLPalette.primary700.withOpacity(0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4;
        canvas.drawCircle(p, 7.6, ring);
      }
    }

    for (int i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: (i < labels.length) ? labels[i] : "",
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: KLPalette.text2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final dx = _clampTextX(xAt(i) - tp.width / 2, tp.width, size.width);
      tp.paint(canvas, Offset(dx, topPad + h + 8));
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueLineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.labels != labels ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}

/// ---------------------------------------------------------------------------
/// Review Themes & Sentiment
/// ---------------------------------------------------------------------------

class _ReviewThemesCard extends StatelessWidget {
  final String providerId;
  const _ReviewThemesCard({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final servicesQ = FirebaseFirestore.instance
        .collection('services')
        .where('providerId', isEqualTo: providerId);

    final reviewsQ = FirebaseFirestore.instance
        .collectionGroup('reviews')
        .where('providerId', isEqualTo: providerId);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: servicesQ.snapshots(),
      builder: (context, servicesSnap) {
        if (servicesSnap.hasError) {
          return Text('Error: ${servicesSnap.error}');
        }

        if (servicesSnap.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 3);
        }

        if (!servicesSnap.hasData) {
          return _Card(
            title: "Review Themes & Sentiment",
            subtitle: "Service-level analyzed feedback",
            headerTrailing: InkWell(
              onTap: () => _showReviewInfo(context),
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.info_outline,
                    color: KLPalette.text2, size: 20),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: reviewsQ.snapshots(),
          builder: (context, reviewsSnap) {
            if (reviewsSnap.hasError) {
              return Text('Error: ${reviewsSnap.error}');
            }

            if (reviewsSnap.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator(minHeight: 3);
            }

            if (servicesSnap.connectionState == ConnectionState.waiting) {
              return _Card(
                title: "Review Themes & Sentiment",
                subtitle: "Service-level analyzed feedback",
                headerTrailing: InkWell(
                  onTap: () => _showReviewInfo(context),
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.info_outline,
                        color: KLPalette.text2, size: 20),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              );
            }

            final services = servicesSnap.data?.docs ?? [];
            final reviews = reviewsSnap.data?.docs ?? [];

            if (services.isEmpty && reviews.isEmpty) {
              return _Card(
                title: "Review Themes & Sentiment",
                subtitle: "Service-level analyzed feedback",
                headerTrailing: InkWell(
                  onTap: () => _showReviewInfo(context),
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.info_outline,
                        color: KLPalette.text2, size: 20),
                  ),
                ),
                child: const Text(
                  "No review insights yet.",
                  style: TextStyle(
                    color: KLPalette.text2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            final serviceNameById = <String, String>{};
            final keywordCounts = <String, int>{};
            final starCounts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

            double weightedSentiment = 0;
            int sentimentWeight = 0;

            double weightedStarsFromServices = 0;
            int starsWeightFromServices = 0;

            DateTime? latestSentimentUpdate;

            for (final d in services) {
              final m = d.data();
              final sid = d.id;
              final serviceName =
              (m['name'] ?? m['title'] ?? 'Service').toString().trim();
              serviceNameById[sid] = serviceName.isEmpty ? 'Service' : serviceName;

              final ratingCount = _ratingCountFromService(m);
              final ratingAvg = _asDouble(m['ratingAvg'] ?? m['rating']);
              if (ratingAvg != null && ratingCount > 0) {
                weightedStarsFromServices += ratingAvg * ratingCount;
                starsWeightFromServices += ratingCount;
              }

              final analyzed = _asInt(m['reviewsAnalyzed']) ?? ratingCount;
              final sentiment = _asDouble(m['sentiment_score']);
              if (sentiment != null && analyzed > 0) {
                weightedSentiment += sentiment * analyzed;
                sentimentWeight += analyzed;
              }

              final updated = _toDateTime(m['sentimentUpdatedAt']);
              if (updated != null) {
                if (latestSentimentUpdate == null ||
                    updated.isAfter(latestSentimentUpdate!)) {
                  latestSentimentUpdate = updated;
                }
              }

              final rawKeywords = m['top_keywords'];
              if (rawKeywords is List) {
                for (final kw in rawKeywords) {
                  final s = kw.toString().trim();
                  if (s.isEmpty) continue;
                  keywordCounts[s] = (keywordCounts[s] ?? 0) + 1;
                }
              }

              final sc = m['starCounts'];
              if (sc is Map) {
                for (final star in [1, 2, 3, 4, 5]) {
                  final val = sc['$star'];
                  starCounts[star] = (starCounts[star] ?? 0) + (_asInt(val) ?? 0);
                }
              }
            }

            double totalStarsFromDocs = 0;
            int verifiedCount = 0;
            final recentExamples = <Map<String, dynamic>>[];

            for (final d in reviews) {
              final m = d.data();
              final stars = _asDouble(m['stars']) ?? 0;
              totalStarsFromDocs += stars;

              if (m['verifiedJob'] == true) verifiedCount++;

              final text = (m['text'] ?? '').toString().trim();
              if (text.isNotEmpty) {
                recentExamples.add({
                  'serviceId': (m['serviceId'] ?? '').toString(),
                  'text': text,
                  'stars': stars,
                  'createdAt': m['createdAt'],
                });
              }
            }

            recentExamples.sort((a, b) {
              final da = _toDateTime(a['createdAt']);
              final db = _toDateTime(b['createdAt']);
              if (da == null && db == null) return 0;
              if (da == null) return 1;
              if (db == null) return -1;
              return db.compareTo(da);
            });

            final totalReviews = reviews.length;
            final avgStars = totalReviews > 0
                ? totalStarsFromDocs / totalReviews
                : (starsWeightFromServices > 0
                ? (weightedStarsFromServices / starsWeightFromServices)
                : 0.0);

            final avgSentiment =
            sentimentWeight > 0 ? (weightedSentiment / sentimentWeight) : null;
            final verifiedPct =
            totalReviews == 0 ? 0.0 : (verifiedCount / totalReviews) * 100.0;

            final sortedKeywords = keywordCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            final topKeywords = sortedKeywords.take(5).toList();
            final topRecent = recentExamples.take(2).toList();

            final subtitle = latestSentimentUpdate == null
                ? "Service-level analyzed feedback"
                : "Service-level analyzed feedback \nUpdated ${_fmtShortDateTime(latestSentimentUpdate!)}";

            return _Card(
              title: "Review Themes & Sentiment",
              subtitle: subtitle,
              headerTrailing: InkWell(
                onTap: () => _showReviewInfo(context),
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child:
                  Icon(Icons.info_outline, color: KLPalette.text2, size: 20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          label: "Sentiment",
                          value: avgSentiment == null
                              ? "-"
                              : avgSentiment.toStringAsFixed(0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniStat(
                          label: "Avg Stars",
                          value: avgStars == 0
                              ? "-"
                              : avgStars.toStringAsFixed(1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MiniStat(
                          label: "Reviews",
                          value: totalReviews.toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Overall tone: ${_sentimentLabel(avgSentiment)}",
                    style: const TextStyle(
                      color: KLPalette.text2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (starCounts.values.any((v) => v > 0)) ...[
                    const Text(
                      "Rating mix",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [5, 4, 3, 2, 1].map((star) {
                        final count = starCounts[star] ?? 0;
                        return _SmallInfoChip(
                          label: "$star★ • $count",
                          highlighted: star >= 4,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (topKeywords.isNotEmpty) ...[
                    const Text(
                      "Top keywords",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: topKeywords.map((e) {
                        return _SmallInfoChip(
                          label: "${e.key} • ${e.value}",
                          highlighted: true,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Keywords are aggregated from each service's analyzed review summary.",
                      style: TextStyle(
                        color: KLPalette.text2,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      "No analyzed keywords yet.",
                      style: TextStyle(
                        color: KLPalette.text2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (topRecent.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      "Recent examples",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    ...topRecent.map((r) {
                      final serviceId = (r['serviceId'] ?? '').toString();
                      final serviceName =
                          serviceNameById[serviceId] ?? 'Service';
                      final stars = _asDouble(r['stars']) ?? 0;
                      final dt = _toDateTime(r['createdAt']);
                      final text = (r['text'] ?? '').toString();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: KLPalette.tint50,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: KLPalette.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "$serviceName • ${stars.toStringAsFixed(0)}★${dt == null ? '' : ' • ${_fmtShortDate(dt)}'}",
                                style: const TextStyle(
                                  color: KLPalette.text2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                text,
                                style:
                                const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showReviewInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "About Review Themes & Sentiment",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                SizedBox(height: 10),
                Text(
                  "This card combines two review insight sources:\n\n"
                      "• Service-level analyzed fields stored on each service document, such as sentiment_score, top_keywords, ratingAvg, ratingCount, reviewsAnalyzed, and starCounts.\n\n"
                      "• Recent written reviews from the review documents for concrete examples.\n\n"
                      "What the numbers mean:\n"
                      "• Sentiment: weighted average sentiment score from analyzed service reviews.\n"
                      "• Avg Stars: average rating across your reviews.\n"
                      "• Reviews: total review documents found for your provider.\n"
                      "• Top keywords: common extracted keywords appearing across your service summaries.\n\n"
                      "Use this card to understand what customers consistently mention and whether overall feedback is improving.",
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
      },
    );
  }
}

class _SmallInfoChip extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _SmallInfoChip({
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted ? KLPalette.tint50 : KLPalette.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: highlighted ? KLPalette.primary700 : KLPalette.text,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Booking Summary
/// ---------------------------------------------------------------------------

class _BookingSummaryCard extends StatelessWidget {
  final String providerId;
  const _BookingSummaryCard({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId);

    return _Card(
      title: "Bookings Summary",
      subtitle: "Live counts and completion rate",
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 3),
            );
          }

          int pending = 0;
          int accepted = 0;
          int confirmed = 0;
          int completed = 0;
          int cancelled = 0;
          int declined = 0;

          for (final d in snap.data!.docs) {
            final s = (d.data()['status'] ?? 'pending')
                .toString()
                .toLowerCase()
                .trim();

            if (s == 'pending') {
              pending++;
            } else if (s == 'accepted') {
              accepted++;
            } else if (s == 'confirmed') {
              confirmed++;
            } else if (s == 'completed') {
              completed++;
            } else if (s == 'cancelled' || s == 'canceled') {
              cancelled++;
            } else if (s == 'declined') {
              declined++;
            }
          }

          final total =
              pending + accepted + confirmed + completed + cancelled + declined;
          final completionRate =
          total == 0 ? 0.0 : (completed / total) * 100.0;
          final openBookings = pending + accepted + confirmed;

          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child:
                    _MiniStat(label: "Pending", value: pending.toString()),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child:
                    _MiniStat(label: "Accepted", value: accepted.toString()),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                        label: "Confirmed", value: confirmed.toString()),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                        label: "Completed", value: completed.toString()),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                        label: "Cancelled", value: cancelled.toString()),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child:
                    _MiniStat(label: "Declined", value: declined.toString()),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "Total: $total • Open: $openBookings • Completion rate: ${completionRate.toStringAsFixed(0)}%",
                style: const TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Revenue Summary
/// ---------------------------------------------------------------------------

bool _isCollectedRevenue(Map<String, dynamic> b) {
  final p = (b['payment'] is Map)
      ? Map<String, dynamic>.from(b['payment'] as Map)
      : <String, dynamic>{};

  final method =
  (p['method'] ?? b['paymentMethod'] ?? '').toString().toLowerCase();
  final state = (p['state'] ?? '').toString().toLowerCase();

  if (state == 'refunded') return false;
  if (method == 'cash') return state == 'cash_received';
  if (method == 'card') return state == 'captured';
  return false;
}

bool _isEarnedRevenue(Map<String, dynamic> b) {
  return (b['status'] ?? '').toString().toLowerCase() == 'completed';
}

class _RevenueSummaryCard extends StatelessWidget {
  final String providerId;
  const _RevenueSummaryCard({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId);

    return _Card(
      title: "Revenue",
      subtitle: "Collected vs Earned",
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 3),
            );
          }

          double collected = 0.0;
          double earned = 0.0;

          for (final d in snap.data!.docs) {
            final b = d.data();
            final amt = _bookingAmountForProvider(b);

            if (_isCollectedRevenue(b)) collected += amt;
            if (_isEarnedRevenue(b)) earned += amt;
          }

          final outstanding = math.max(0.0, earned - collected);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: "Collected",
                      value: _fmtRmCompact(collected),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                      label: "Earned",
                      value: _fmtRmCompact(earned),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "Outstanding gap: ${_fmtRmCompact(outstanding)}",
                style: const TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Collected = cash received / card captured \nEarned = completed jobs",
                style: TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Shared Card Widgets
/// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? headerTrailing;

  const _Card({
    required this.title,
    required this.subtitle,
    required this.child,
    this.headerTrailing,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
                if (headerTrailing != null) ...[
                  const SizedBox(width: 8),
                  headerTrailing!,
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                  color: KLPalette.text2, fontWeight: FontWeight.w700),
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
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
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

class _CircleBrand extends StatelessWidget {
  const _CircleBrand();

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        height: 48,
        width: 48,
        color: KLPalette.mutedBg,
        child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Shared Helpers
/// ---------------------------------------------------------------------------

bool _isCompletedBooking(Map<String, dynamic> m) {
  final status =
  (m['status'] ?? m['bookingStatus'] ?? m['state'])?.toString().toLowerCase().trim();

  final boolFlag = m['isCompleted'];
  if (boolFlag is bool && boolFlag == true) return true;

  final completedAt = m['completedAt'];
  if (completedAt is Timestamp) return true;
  if (completedAt is DateTime) return true;

  if (status == null) return false;

  const completedWords = {
    'completed',
    'complete',
    'done',
    'finished',
    'success',
    'successful',
  };
  return completedWords.contains(status);
}

double _bookingAmountForProvider(Map<String, dynamic> m) {
  final candidates = <dynamic>[
    m['providerEarning'],
    m['providerPayout'],
    m['providerNet'],
    (m['payout'] is Map) ? (m['payout'] as Map)['provider'] : null,
    (m['payment'] is Map) ? (m['payment'] as Map)['providerAmount'] : null,
    m['totalPrice'],
    m['totalAmount'],
    m['amount'],
    m['price'],
    (m['pricing'] is Map) ? (m['pricing'] as Map)['total'] : null,
    (m['pricing'] is Map) ? (m['pricing'] as Map)['amount'] : null,
  ];

  for (final v in candidates) {
    final d = _asDouble(v);
    if (d != null) return d;
  }
  return 0;
}

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

DateTime? _toDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate().toLocal();
  if (v is DateTime) return v.toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

int _ratingCountFromService(Map<String, dynamic> m) {
  final ratingCount = _asInt(m['ratingCount']);
  if (ratingCount != null && ratingCount > 0) return ratingCount;

  final analyzed = _asInt(m['reviewsAnalyzed']);
  if (analyzed != null && analyzed > 0) return analyzed;

  final sc = m['starCounts'];
  if (sc is Map) {
    int total = 0;
    for (final star in [1, 2, 3, 4, 5]) {
      total += _asInt(sc['$star']) ?? 0;
    }
    return total;
  }

  return 0;
}

String _sentimentLabel(double? score) {
  if (score == null) return "No sentiment yet";
  if (score >= 70) return "Positive";
  if (score >= 45) return "Mixed";
  return "Needs attention";
}

int? _monthIndex(List<DateTime> monthStarts, DateTime dt) {
  for (int i = 0; i < monthStarts.length; i++) {
    final ms = monthStarts[i];
    if (ms.year == dt.year && ms.month == dt.month) return i;
  }
  return null;
}

String _monLabel(DateTime d) {
  const names = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
  ];
  return names[d.month - 1];
}

String _fmtShortDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return "$dd/$mm/${d.year}";
}

String _fmtShortDateTime(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return "$dd/$mm $hh:$mi";
}

String _fmtRmCompact(double v) {
  final n = v.isFinite ? v : 0.0;
  final abs = n.abs();

  String fmt(double x, {int dp = 1}) {
    final s = x.toStringAsFixed(dp);
    if (s.endsWith('.0')) return s.substring(0, s.length - 2);
    return s;
  }

  if (abs >= 1000000) return "RM ${fmt(n / 1000000)}M";
  if (abs >= 1000) return "RM ${fmt(n / 1000)}k";
  return "RM ${n.toStringAsFixed(0)}";
}