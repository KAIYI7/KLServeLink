import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'provider_dashboard_tab.dart' show ProviderHighOpportunityScreen;

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
                    _BookingSummaryCard(providerId: uid),
                    const SizedBox(height: 12),
                    _RevenueSummaryCard(providerId: uid),
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

/// --- High Opportunity Hours (AI opportunity_index, fallback to heuristic) ---
class _HighOpportunityCard extends StatelessWidget {
  final String providerId;
  const _HighOpportunityCard({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // --- Heuristic window (past) for bookings ---
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)); // tomorrow 00:00
    final start = end.subtract(const Duration(days: 28)); // last 28 days

    // --- AI horizon (future) for opportunity_index slots ---
    final aiStart = DateTime(now.year, now.month, now.day); // today 00:00
    final aiEnd = aiStart.add(const Duration(days: 7));     // next 7 days


    final bookingsQ = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end));

    final userRef = FirebaseFirestore.instance.collection('users').doc(providerId);

    final workingHoursDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(providerId);

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
              child: const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            ),
          );
        }

        final userData = userSnap.data!.data() ?? const <String, dynamic>{};

        // --- AI slots ---
        final opp = userData['opportunity_index'];
        final oppMap = (opp is Map) ? Map<String, dynamic>.from(opp as Map) : null;

        final algo = oppMap?['algo']?.toString();
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
              final data = Map<String, dynamic>.from(
                whSnap.data!.data()!,
              );

              workingHoursRaw = Map<String, dynamic>.from(
                data['workingHours'] ?? {},
              );
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

            // Fallback: heuristic
            return _TappableCard(
              onTap: openDrilldown,
              child: _Card(
                title: "High-Opportunity Hours",
                subtitle: "Next 7 days (heuristic)",
                child: Column(
                  children: [
                    _HeuristicOppBars(
                      bookingsQ: bookingsQ,
                      start: start,
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
    final slots = <({DateTime dt, double score, double? rev, double? bk, double? views, double? conv})>[];

    for (final m in slotsRaw) {
      final ts = m['startAt'];
      DateTime? dt;
      if (ts is Timestamp) dt = ts.toDate();
      if (ts is DateTime) dt = ts;

      final score = _d(m['score']) ?? 0;
      final rev = _d(m['expectedRevenue']);
      final bk = _d(m['expectedBookings']);
      final views = _d(m['expectedViews']);
      final conv = _d(m['expectedConversionRate']); // 0..1

      if (dt != null) {
        final local = dt.toLocal();

        // horizon filter
        if (local.isBefore(start) || !local.isBefore(end)) continue;

        // working hours filter
        if (workingHoursRaw.isNotEmpty &&
            !_HeuristicOppBars._isWithinWorkingHoursStrict(local, workingHoursRaw)) {
          continue;
        }

        slots.add((dt: local, score: score, rev: rev, bk: bk, views: views, conv: conv));
      }
    }

    if (slots.isEmpty) {
      return const Text(
        "AI forecast exists but no suggested slots match your Working Hours in the next 7 days.",
        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
      );
    }

    // Prefer ranking by expectedRevenue if present, else score
    slots.sort((a, b) {
      final av = (a.rev ?? -1);
      final bv = (b.rev ?? -1);
      if (av >= 0 && bv >= 0 && av != bv) return bv.compareTo(av);
      return b.score.compareTo(a.score);
    });

    final top = slots.take(5).toList();

    final maxBar = top
        .map((e) => e.rev ?? e.score)
        .fold<double>(0, (p, v) => (v > p) ? v : p);
    final denom = (maxBar <= 0) ? 1.0 : maxBar;

    return Column(
      children: [
        ...top.map((e) {
          final dt = e.dt;
          final label = "${_wdShort(dt.weekday)} ${dt.hour.toString().padLeft(2, '0')}:00";

          final barVal = (e.rev ?? e.score) / denom;

          final revText = (e.rev == null) ? "-" : "Est. RM ${e.rev!.toStringAsFixed(0)}";
          final convText = (e.conv == null) ? null : "${(e.conv! * 100).toStringAsFixed(1)}%";
          final viewsText = (e.views == null) ? null : "${e.views!.toStringAsFixed(0)} views";

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: barVal.isNaN ? 0 : barVal.clamp(0, 1),
                      minHeight: 10,
                      backgroundColor: KLPalette.tint50,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(revText, style: const TextStyle(fontWeight: FontWeight.w900)),
                    if (convText != null || viewsText != null)
                      Text(
                        [convText, viewsText].whereType<String>().join(" • "),
                        style: const TextStyle(
                          fontSize: 11,
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        const Text(
          "Est. RM is predicted revenue for that hour (planning estimate).",
          style: TextStyle(
            color: KLPalette.text2,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    );
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
}


class _HeuristicOppBars extends StatelessWidget {
  final Query<Map<String, dynamic>> bookingsQ;
  final DateTime start;
  final Map<String, dynamic> workingHoursRaw;

  const _HeuristicOppBars({
    required this.bookingsQ,
    required this.start,
    required this.workingHoursRaw,
  });

  @override
  Widget build(BuildContext context) {
    final hasWorkingHours = workingHoursRaw.isNotEmpty;

    // Build allowed-hours map for the next 7 days
    final allowedHours = List<bool>.filled(24, true);
    if (hasWorkingHours) {
      for (var i = 0; i < 24; i++) {
        allowedHours[i] = false;
      }
      for (int i = 0; i < 7; i++) {
        final day = start.add(Duration(days: i));
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
            style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
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

  static bool _isWithinWorkingHoursStrict(DateTime dt, Map<String, dynamic> workingHours) {
    if (workingHours.isEmpty) return true;

    final key = _weekdayKey(dt);
    final day = workingHours[key];
    if (day is! Map) return false; // missing/malformed => closed

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


/// --- Booking Summary (counts by status) ---
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
      subtitle: "Live counts",
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 3),
            );
          }

          int pending = 0, accepted = 0, completed = 0;
          for (final d in snap.data!.docs) {
            final s = (d.data()['status'] ?? 'pending').toString();
            if (s == 'pending') pending++;
            if (s == 'accepted') accepted++;
            if (s == 'completed') completed++;
          }

          return Row(
            children: [
              Expanded(child: _MiniStat(label: "Pending", value: pending.toString())),
              const SizedBox(width: 10),
              Expanded(child: _MiniStat(label: "Accepted", value: accepted.toString())),
              const SizedBox(width: 10),
              Expanded(child: _MiniStat(label: "Completed", value: completed.toString())),
            ],
          );
        },
      ),
    );
  }
}

/// --- 3) Revenue Summary (sum completed) ---
class _RevenueSummaryCard extends StatelessWidget {
  final String providerId;
  const _RevenueSummaryCard({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId)
        .where('status', isEqualTo: 'completed');

    return _Card(
      title: "Revenue",
      subtitle: "From completed bookings",
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 3),
            );
          }

          double total = 0;
          for (final d in snap.data!.docs) {
            final n = d.data()['totalAmount'];
            if (n is num) total += n.toDouble();
          }

          return Row(
            children: [
              const Icon(Icons.insights_rounded, color: KLPalette.primary),
              const SizedBox(width: 10),
              Text(
                "RM ${total.toStringAsFixed(2)}",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// --- shared UI ---
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
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
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800)),
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
