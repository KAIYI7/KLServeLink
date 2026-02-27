import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/utils/app_snack.dart';
import 'theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ui_components.dart';
import 'notifications/notifications_screen.dart';
import 'data/provider_services_repo.dart';
import 'provider_services_tab.dart';
import 'provider_service_detail_screen.dart';
import 'provider_shell_scope.dart';
import 'provider_profile_tab.dart';

class ProviderDashboardTab extends StatelessWidget {
  const ProviderDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              const _TopBar(),
              const SizedBox(height: 14),

              const _StatsGrid(),
              const SizedBox(height: 14),

              const _HighOpportunityPreviewCard(),
              const SizedBox(height: 18),

              const _SectionHeader(title: "Monthly Revenue (RM)"),
              const SizedBox(height: 12),
              const _RevenueChartPlaceholder(),
              const SizedBox(height: 18),

              _SectionHeader(
                title: "Services",
                action: "View All",
                onActionTap: () {
                  final scope = ProviderShellScope.of(context);
                  if (scope != null) {
                    scope.setIndex(1); // Services tab
                    return;
                  }

                  // Fallback (if Dashboard is ever used outside ProviderShell)
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProviderServicesTab()),
                  );
                },
              ),

              const SizedBox(height: 12),
              const _ServicesGrid(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left: brand
          const Align(
            alignment: Alignment.centerLeft,
            child: _CircleBrand(),
          ),

          // Center: title (always centered)
          const Center(
            child: Text(
              "Dashboard",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            ),
          ),

          // Right: actions
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _notifUnreadStream(),
                  builder: (context, snap) {
                    final hasUnread = (snap.data?.docs.isNotEmpty ?? false);

                    return CircleIconButton(
                      icon: Icons.notifications_none_rounded,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(isProvider: true),
                          ),
                        );
                      },
                      size: 48,
                      badge: hasUnread ? const NotificationDot() : null,
                    );
                  },
                ),
                const SizedBox(width: 10),
                const _ProfileShortcutButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _notifUnreadStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .limit(1)
        .snapshots();
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
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
          const Icon(Icons.storefront_rounded, color: KLPalette.text2),
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

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

class _ProfileShortcutButton extends StatelessWidget {
  const _ProfileShortcutButton();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    void goProfile() {
      if (uid == null) {
        AppSnack.show(context, "Please login", type: AppSnackType.error);
        return;
      }

      final scope = ProviderShellScope.of(context);
      if (scope != null) {
        scope.setIndex(5);
        return;
      }

      // Fallback (if Dashboard is ever used outside ProviderShell)
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProviderProfileTab()),
      );
    }

    if (uid == null) {
      return _CircleIcon(icon: Icons.person_outline, onTap: goProfile);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final photoUrl = (data['photoUrl'] ?? '').toString().trim();

        return InkWell(
          onTap: goProfile,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: KLPalette.mutedBg,
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: ClipOval(
              child: (photoUrl.isNotEmpty)
                  ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.person_outline,
                  color: KLPalette.text,
                ),
              )
                  : const Icon(Icons.person_outline, color: KLPalette.text),
            ),
          ),
        );
      },
    );
  }
}

class _CommissionCard extends StatelessWidget {
  const _CommissionCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: KLPalette.mutedBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Commission Type: Company",
                      style: TextStyle(
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text("My Commission: RM 20 (Fixed)",
                      style:
                      TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ],
              ),
            ),
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: KLPalette.tint100,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child:
              const Icon(Icons.percent_rounded, color: KLPalette.primary700),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _statsGridFrom(
        const [
          _StatData(
              label: "Total Bookings",
              value: "-",
              icon: Icons.calendar_month_rounded),
          _StatData(
              label: "Total Services",
              value: "-",
              icon: Icons.storefront_rounded),
          _StatData(
            label: "Completed Jobs",
            value: "-",
            icon: Icons.check_circle_rounded,
          ),
          _StatData(
              label: "Total Earning",
              value: "-",
              icon: Icons.payments_rounded),
        ],
      );
    }

    final bookingsQ = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: uid);

    final servicesQ = FirebaseFirestore.instance
        .collection('services')
        .where('providerId', isEqualTo: uid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: bookingsQ.snapshots(),
      builder: (context, bookingsSnap) {
        if (bookingsSnap.hasError) {
          return _statsGridFrom(
            const [
              _StatData(
                  label: "Total Bookings",
                  value: "Err",
                  icon: Icons.calendar_month_rounded),
              _StatData(
                  label: "Total Services",
                  value: "Err",
                  icon: Icons.storefront_rounded),
              _StatData(
                label: "Completed Jobs",
                value: "Err",
                icon: Icons.check_circle_rounded,
              ),
              _StatData(
                  label: "Total Earning",
                  value: "Err",
                  icon: Icons.payments_rounded),
            ],
          );
        }

        if (!bookingsSnap.hasData) {
          return _statsGridLoading();
        }

        final bookingDocs = bookingsSnap.data!.docs;

        final totalBookings = bookingDocs.length;
        int completedJobs = 0;
        double totalEarning = 0;

        for (final d in bookingDocs) {
          final m = d.data();
          final completed = _isCompletedBooking(m);
          if (completed) {
            completedJobs += 1;
            totalEarning += _bookingEarning(m);
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: servicesQ.snapshots(),
          builder: (context, servicesSnap) {
            if (!servicesSnap.hasData) {
              return _statsGridLoading();
            }

            final totalServices = servicesSnap.data!.docs.length;

            final stats = [
              _StatData(
                label: "Total Bookings",
                value: totalBookings.toString(),
                icon: Icons.calendar_month_rounded,
              ),
              _StatData(
                label: "Total Services",
                value: totalServices.toString(),
                icon: Icons.storefront_rounded,
              ),
              _StatData(
                label: "Completed Jobs",
                value: completedJobs.toString(),
                icon: Icons.check_circle_rounded,
              ),
              _StatData(
                label: "Total Earning",
                value: _fmtRmCompact(totalEarning),
                icon: Icons.payments_rounded,
              ),
            ];

            return _statsGridFrom(stats);
          },
        );
      },
    );
  }

  Widget _statsGridLoading() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: const LinearProgressIndicator(minHeight: 3),
      ),
    );
  }

  Widget _statsGridFrom(List<_StatData> stats) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.65,
      ),
      itemBuilder: (_, i) => _StatCard(d: stats[i]),
    );
  }

  bool _isCompletedBooking(Map<String, dynamic> m) {
    final status = (m['status'] ?? m['bookingStatus'] ?? m['state'])
        ?.toString()
        .toLowerCase()
        .trim();

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

  double _bookingEarning(Map<String, dynamic> m) {
    // Prefer provider-specific net/payout fields, fallback to booking total fields.
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
}

class _StatData {
  final String label;
  final String value;
  final IconData icon;
  const _StatData({required this.label, required this.value, required this.icon});
}

class _StatCard extends StatelessWidget {
  final _StatData d;
  const _StatCard({required this.d});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.value,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 22)),
                  const SizedBox(height: 6),
                  Text(d.label,
                      style: const TextStyle(
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: KLPalette.tint50,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: Icon(d.icon, size: 18, color: KLPalette.primary700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onActionTap;

  const _SectionHeader({
    required this.title,
    this.action,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const Spacer(),
        if (action != null)
          InkWell(
            onTap: onActionTap ??
                    () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("$action (TODO)")),
                  );
                },
            child: Text(
              action!,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: KLPalette.primary700),
            ),
          ),
      ],
    );
  }
}

class _RevenueChartPlaceholder extends StatelessWidget {
  const _RevenueChartPlaceholder();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _revenueShell(
        months: const ["-", "-", "-", "-", "-", "-", "-", "-"],
        fractions: const [0, 0, 0, 0, 0, 0, 0, 0],
        caption: "Sign in to view revenue.",
        onTap: null,
      );
    }

    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 7, 1);
    final end = DateTime(now.year, now.month + 1, 1);

    final q = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: uid)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _revenueLoading();
        }
        if (snap.hasError) {
          return _revenueShell(
            months: _last8MonthLabels(now),
            fractions: List.filled(8, 0),
            caption: "Unable to load revenue (check rules/index).",
            onTap: null,
          );
        }

        final docs = snap.data!.docs;

        // Build month buckets for last 8 months
        final monthsDt = List.generate(8, (i) {
          final d = DateTime(now.year, now.month - 7 + i, 1);
          return d;
        });

        final totals = List<double>.filled(8, 0);

        for (final d in docs) {
          final m = d.data();

          // Only count completed bookings into revenue
          if (!_isCompletedBookingForRevenue(m)) continue;

          final ts = m['scheduledAt'];
          DateTime? dt;
          if (ts is Timestamp) dt = ts.toDate().toLocal();
          if (ts is DateTime) dt = ts.toLocal();
          if (dt == null) continue;

          final idx = _monthIndex(monthsDt, dt);
          if (idx == null) continue;

          totals[idx] += _bookingRevenue(m);
        }

        final maxV = totals.fold<double>(0, (p, v) => math.max(p, v));
        final fracs = totals
            .map((v) => (maxV <= 0) ? 0.0 : (v / maxV).clamp(0.0, 1.0))
            .toList();

        final labels = monthsDt.map(_monLabel).toList();
        final total8 = totals.fold<double>(0, (p, v) => p + v);

        return _revenueShell(
          months: labels,
          fractions: fracs,
          caption:
          "Last 8 months • Total ${_fmtRmCompact(total8)} • Tap for details",
          onTap: () => _showRevenueDetails(context, monthsDt, totals),
        );
      },
    );
  }

  Widget _revenueLoading() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: const LinearProgressIndicator(minHeight: 3),
      ),
    );
  }

  Widget _revenueShell({
    required List<String> months,
    required List<double> fractions,
    required String caption,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: KLPalette.bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: KLPalette.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(months.length, (i) {
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
                            Text(months[i],
                                style: const TextStyle(
                                    color: KLPalette.text2,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    caption,
                    style: const TextStyle(
                        color: KLPalette.text2,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _showRevenueDetails(
      BuildContext context,
      List<DateTime> months,
      List<double> totals,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _RevenueDetailsSheet(months: months, totals: totals),
    );
  }

  static List<String> _last8MonthLabels(DateTime now) {
    final months =
    List.generate(8, (i) => DateTime(now.year, now.month - 7 + i, 1));
    return months.map(_monLabel).toList();
  }

  static String _monLabel(DateTime d) {
    const names = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return names[d.month - 1];
  }

  static int? _monthIndex(List<DateTime> monthStarts, DateTime dt) {
    for (int i = 0; i < monthStarts.length; i++) {
      final ms = monthStarts[i];
      if (ms.year == dt.year && ms.month == dt.month) return i;
    }
    return null;
  }

  bool _isCompletedBookingForRevenue(Map<String, dynamic> m) {
    final status = (m['status'] ?? m['bookingStatus'] ?? m['state'])
        ?.toString()
        .toLowerCase()
        .trim();

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

  double _bookingRevenue(Map<String, dynamic> m) {
    final candidates = <dynamic>[
      m['totalPrice'],
      m['totalAmount'],
      m['amount'],
      (m['pricing'] is Map) ? (m['pricing'] as Map)['total'] : null,
      (m['pricing'] is Map) ? (m['pricing'] as Map)['amount'] : null,
      m['providerEarning'],
      m['providerPayout'],
      (m['payment'] is Map) ? (m['payment'] as Map)['providerAmount'] : null,
    ];

    for (final v in candidates) {
      final d = _asDouble(v);
      if (d != null) return d;
    }
    return 0;
  }
}

class _RevenueDetailsSheet extends StatelessWidget {
  final List<DateTime> months;
  final List<double> totals;

  const _RevenueDetailsSheet({
    required this.months,
    required this.totals,
  });

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

    String monYear(DateTime d) =>
        "${_RevenueChartPlaceholder._monLabel(d)} ${d.year}";

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
                      "Monthly Revenue",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
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
                  Expanded(child: _MiniKpiCard(label: "Total", value: _fmtRmCompact(total))),
                  const SizedBox(width: 10),
                  Expanded(child: _MiniKpiCard(label: "Avg / month", value: _fmtRmCompact(avg))),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniKpiCard(
                      label: "Best month",
                      value: "${_RevenueChartPlaceholder._monLabel(months[bestIdx])} • ${_fmtRmCompact(bestVal)}",
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
                labels: months.map((d) => _RevenueChartPlaceholder._monLabel(d)).toList(),
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
                    "• Amount is derived from your booking’s total fields (e.g. totalAmount / pricing.total).",
                style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
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
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: KLPalette.text2, fontWeight: FontWeight.w800)),
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

    _hideTimer?.cancel(); // keep visible while interacting

    if (toggle) {
      // Tap: toggle on same point
      setState(() {
        _selectedIndex = (_selectedIndex == idx) ? null : idx;
      });
    } else {
      // Drag: DO NOT toggle, just set (and only rebuild when idx changes)
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
              // Tap toggles
              onTapDown: (d) => _handleTouch(d.localPosition, size, toggle: true),
              onTapUp: (_) => _scheduleHide(),

              // Drag sticks
              onPanDown: (d) => _handleTouch(d.localPosition, size, toggle: false),
              onPanUpdate: (d) => _handleTouch(d.localPosition, size, toggle: false),
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

    // baseline
    final gridPaint = Paint()
      ..color = KLPalette.border
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(leftPad, topPad + h),
      Offset(leftPad + w, topPad + h),
      gridPaint,
    );

    // mid grid lines (25/50/75%)
    for (final frac in const [0.25, 0.5, 0.75]) {
      final y = topPad + h * (1 - frac);
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + w, y), gridPaint);
    }

    // line path
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

    // crosshair for selected
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

    // points
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

    // x labels (clamped so first/last don’t get cut off)
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

class _WorkersGrid extends StatelessWidget {
  const _WorkersGrid();

  @override
  Widget build(BuildContext context) {
    // (Not used on dashboard right now)
    final people = const [
      _Person(name: "Rickey Ledner"),
      _Person(name: "Jarvis Robel"),
      _Person(name: "Araceli Ryan"),
      _Person(name: "Trudie Rice"),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: people.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (_, i) => _WorkerCard(p: people[i]),
    );
  }
}

class _Person {
  final String name;
  const _Person({required this.name});
}

class _WorkerCard extends StatelessWidget {
  final _Person p;
  const _WorkerCard({required this.p});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: KLPalette.mutedBg,
                alignment: Alignment.center,
                child:
                const Icon(Icons.person, size: 54, color: KLPalette.text2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _MiniAction(icon: Icons.call_rounded, onTap: () {}),
                      const SizedBox(width: 10),
                      _MiniAction(
                          icon: Icons.mail_outline_rounded, onTap: () {}),
                      const SizedBox(width: 10),
                      _MiniAction(
                          icon: Icons.chat_bubble_outline_rounded, onTap: () {}),
                    ],
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

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 34,
        width: 34,
        decoration: BoxDecoration(
          color: KLPalette.tint50,
          shape: BoxShape.circle,
          border: Border.all(color: KLPalette.border),
        ),
        child: Icon(icon, size: 16, color: KLPalette.primary700),
      ),
    );
  }
}

class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _servicesEmpty("Sign in to view your services.");
    }

    final repo = ProviderServicesRepo();

    return StreamBuilder<List<ProviderServiceUi>>(
      stream: repo.watchMyServices(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _servicesEmpty("Unable to load services (check rules/index).");
        }
        if (!snap.hasData) {
          return _servicesLoading();
        }

        final services = snap.data!
            .where((s) => s.name.trim().isNotEmpty)
            .toList();

        // Sort: rating desc, then price asc
        services.sort((a, b) {
          final r = b.ratingAvg.compareTo(a.ratingAvg);
          if (r != 0) return r;
          return a.price.compareTo(b.price);
        });

        final top = services.take(4).toList();

        if (top.isEmpty) {
          return _servicesEmpty("No services yet. Create one to show here.");
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: top.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemBuilder: (_, i) => _ProviderServiceCard(s: top[i]),
        );
      },
    );
  }

  Widget _servicesLoading() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: const LinearProgressIndicator(minHeight: 3),
      ),
    );
  }

  Widget _servicesEmpty(String msg) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.tint50,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Text(
          msg,
          style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ProviderServiceCard extends StatelessWidget {
  final ProviderServiceUi s;
  const _ProviderServiceCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final priceText = "RM ${s.price.toStringAsFixed(0)}";
    final ratingText = s.ratingAvg.toStringAsFixed(1);
    final categoryText = s.category.trim().isEmpty ? "Category" : s.category;

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderServiceDetailScreen(service: s),
          ),
        );
      },
      borderRadius: BorderRadius.circular(22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: KLPalette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 110,
                width: double.infinity,
                child: _ServiceCoverImage(s: s),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: Color(0xFFFBBF24)),
                        const SizedBox(width: 4),
                        Text(ratingText,
                            style: const TextStyle(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: KLPalette.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            priceText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(categoryText,
                        style: const TextStyle(
                            color: KLPalette.text2,
                            fontWeight: FontWeight.w700)),
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

class _Service {
  final String id;
  final String title;
  final double? price;
  final double? rating;
  final String? category;
  final String? imageUrl;

  const _Service({
    required this.id,
    required this.title,
    this.price,
    this.rating,
    this.category,
    this.imageUrl,
  });

  factory _Service.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};

    final title = (m['title'] ??
        m['name'] ??
        m['serviceName'] ??
        m['listingTitle'] ??
        '')
        .toString();

    // category can be a string or a map
    String? category;
    final c0 = m['category'];
    if (c0 is String) category = c0;
    if (c0 is Map) {
      category = (c0['name'] ?? c0['title'] ?? c0['label'])?.toString();
    }
    category ??= (m['categoryName'] ?? m['primaryCategory'])?.toString();

    // rating can be a number or nested in stats
    double? rating = _asDouble(m['ratingAvg']) ??
        _asDouble(m['rating']) ??
        _asDouble(m['avgRating']);
    if (rating == null && m['stats'] is Map) {
      final s = (m['stats'] as Map).cast<String, dynamic>();
      rating = _asDouble(s['ratingAvg']) ?? _asDouble(s['avgRating']);
    }

    // price can be a number or nested in pricing
    double? price = _asDouble(m['price']) ??
        _asDouble(m['basePrice']) ??
        _asDouble(m['startingPrice']) ??
        _asDouble(m['minPrice']);
    if (price == null && m['pricing'] is Map) {
      final p = (m['pricing'] as Map).cast<String, dynamic>();
      price = _asDouble(p['price']) ??
          _asDouble(p['base']) ??
          _asDouble(p['starting']);
    }

    // image url (optional)
    String? imageUrl = (m['imageUrl'] ?? m['coverUrl'] ?? m['thumbnailUrl'])?.toString();
    if ((imageUrl == null || imageUrl.trim().isEmpty) && m['images'] is List) {
      final imgs = (m['images'] as List).whereType<dynamic>().toList();
      if (imgs.isNotEmpty) {
        final first = imgs.first;
        if (first is String) imageUrl = first;
        if (first is Map) imageUrl = (first['url'] ?? first['downloadUrl'])?.toString();
      }
    }

    return _Service(
      id: d.id,
      title: title,
      price: price,
      rating: rating,
      category: category,
      imageUrl: imageUrl,
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final _Service s;
  const _ServiceCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final priceText = (s.price == null)
        ? "RM -"
        : "RM ${s.price!.toStringAsFixed(0)}";

    final ratingText = (s.rating == null) ? "-" : s.rating!.toStringAsFixed(1);
    final categoryText = (s.category == null || s.category!.trim().isEmpty)
        ? "Category"
        : s.category!;

    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Open service ${s.id} (TODO)")),
        );
      },
      borderRadius: BorderRadius.circular(22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: KLPalette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Container(
                height: 110,
                width: double.infinity,
                color: KLPalette.mutedBg,
                alignment: Alignment.center,
                child: (s.imageUrl != null && s.imageUrl!.trim().isNotEmpty)
                    ? Image.network(
                  s.imageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 110,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 44, color: KLPalette.text2),
                )
                    : const Icon(Icons.image, size: 44, color: KLPalette.text2),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: Color(0xFFFBBF24)),
                        const SizedBox(width: 4),
                        Text(ratingText,
                            style:
                            const TextStyle(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: KLPalette.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            priceText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(categoryText,
                        style: const TextStyle(
                            color: KLPalette.text2,
                            fontWeight: FontWeight.w700)),
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

class _HighOpportunityPreviewCard extends StatelessWidget {
  const _HighOpportunityPreviewCard();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProviderHighOpportunityScreen(providerId: uid),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: KLPalette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      "High-Opportunity Hours",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "Tap to see recommended hours by day (next 7 days).",
                style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),

              // show quick preview (top 3 days overall, one per day)
              _HighOppPreviewList(providerId: uid),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighOppPreviewList extends StatelessWidget {
  final String providerId;
  const _HighOppPreviewList({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(providerId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(minHeight: 3),
          );
        }

        final data = userSnap.data?.data() ?? const <String, dynamic>{};

        // Working Hours
        final workingHoursRaw = (data['workingHours'] is Map)
            ? (data['workingHours'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};

        final availability = _HighOppDrilldownList._parseWorkingHours(workingHoursRaw);
        final hasWhFilter = workingHoursRaw.isNotEmpty;

        bool allow(DateTime dtLocal) {
          if (!hasWhFilter) return true;
          final allowed = availability[dtLocal.weekday] ?? const <int>[];
          return allowed.contains(dtLocal.hour);
        }

        // Next 7 days horizon
        final now = DateTime.now();
        final day0 = DateTime(now.year, now.month, now.day);
        final dayEnd = day0.add(const Duration(days: 7));

        // AI slots
        final opp = data['opportunity_index'];
        final oppMap = (opp is Map) ? Map<String, dynamic>.from(opp as Map) : null;

        final slotsRaw = oppMap?['slots'];
        final slotsList = (slotsRaw is List) ? slotsRaw : const [];

        // If AI exists, filter by horizon + working hours, then pick top 3 days (one best slot per day)
        // Prefer within-Working-Hours when available; otherwise show outside-WH.
        if (slotsList.isNotEmpty) {
          // dayKey -> best slot inside WH
          final bestInByDay = <DateTime, ({DateTime dt, double score, double? rev, bool outsideWh})>{};
          // dayKey -> best slot outside WH
          final bestOutByDay = <DateTime, ({DateTime dt, double score, double? rev, bool outsideWh})>{};

          double metric(double? r, double s) => (r ?? s);

          for (final m0 in slotsList.whereType<Map>()) {
            final m = Map<String, dynamic>.from(m0);

            final ts = m['startAt'];
            DateTime? dt;
            if (ts is Timestamp) dt = ts.toDate();
            else if (ts is DateTime) dt = ts;

            if (dt == null) continue;

            final local = dt.toLocal();
            if (local.isBefore(day0) || !local.isBefore(dayEnd)) continue;

            final score = (m['score'] as num?)?.toDouble() ?? 0;
            final rev = (m['expectedRevenue'] as num?)?.toDouble();
            final dayKey = DateTime(local.year, local.month, local.day);

            final withinWh = !hasWhFilter ? true : allow(local);
            final rec = (dt: local, score: score, rev: rev, outsideWh: hasWhFilter && !withinWh);

            if (withinWh) {
              final prev = bestInByDay[dayKey];
              if (prev == null || metric(rev, score) > metric(prev.rev, prev.score)) {
                bestInByDay[dayKey] = rec;
              }
            } else {
              final prev = bestOutByDay[dayKey];
              if (prev == null || metric(rev, score) > metric(prev.rev, prev.score)) {
                bestOutByDay[dayKey] = rec;
              }
            }
          }

          // Build final per-day choice: prefer in-WH, else outside-WH
          final chosen = <({DateTime dt, double score, double? rev, bool outsideWh})>[];
          final allDays = <DateTime>{
            ...bestInByDay.keys,
            ...bestOutByDay.keys,
          };

          for (final d in allDays) {
            final pick = bestInByDay[d] ?? bestOutByDay[d];
            if (pick != null) chosen.add(pick);
          }

          if (chosen.isNotEmpty) {
            chosen.sort((a, b) {
              final av = a.rev ?? a.score;
              final bv = b.rev ?? b.score;
              return bv.compareTo(av);
            });

            final top = chosen.take(3).toList();

            const outsideBg = Color(0xFFFFFBEB);
            const outsideText = Color(0xFFB45309);

            return Column(
              children: top.map((e) {
                final dt = e.dt;
                final label = "${_wdShort(dt.weekday)} ${dt.day}/${dt.month} • ${_fmtHour(dt.hour)}";

                final badgeText = (e.rev != null)
                    ? "Est. RM ${e.rev!.toStringAsFixed(0)}"
                    : "Score ${e.score.toStringAsFixed(0)}";

                final bg = e.outsideWh ? outsideBg : KLPalette.tint50;
                final textColor = e.outsideWh ? outsideText : KLPalette.primary700;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: KLPalette.border),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          }

          // AI exists but nothing in horizon
          if (hasWhFilter) {
            return _AvailableOppPreviewList(availability: availability, day0: day0);
          }

          return const Text(
            "AI forecast exists but no upcoming suggested days (next 7 days).",
            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
          );
        }

        // Fallback to heuristic
        return _HeuristicOppPreviewList(
          providerId: providerId,
          workingHoursRaw: workingHoursRaw,
        );
      },
    );
  }

  static String _fmtHour(int h) => "${h.toString().padLeft(2, '0')}:00";

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

class _AvailableOppPreviewList extends StatelessWidget {
  final Map<int, List<int>> availability; // weekday(1..7) -> allowed hours
  final DateTime day0; // start of today

  const _AvailableOppPreviewList({
    required this.availability,
    required this.day0,
  });

  @override
  Widget build(BuildContext context) {
    final daySlots = <DateTime>[];

    for (int i = 0; i < 7; i++) {
      final d = day0.add(Duration(days: i));
      final allowed = availability[d.weekday] ?? const <int>[];
      if (allowed.isEmpty) continue;

      // one per day: pick earliest available hour
      final h = (allowed.toList()..sort()).first;
      daySlots.add(DateTime(d.year, d.month, d.day, h));
    }

    final top = daySlots.take(3).toList();

    if (top.isEmpty) {
      return const Text(
        "Closed (Working Hours disabled).",
        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
      );
    }

    return Column(
      children: top.map((dt) {
        final label =
            "${_HighOppPreviewList._wdShort(dt.weekday)} ${dt.day}/${dt.month} • ${_HighOppPreviewList._fmtHour(dt.hour)}";

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: KLPalette.tint50,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: KLPalette.border),
                ),
                child: const Text(
                  "Available",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: KLPalette.primary700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _HeuristicOppPreviewList extends StatelessWidget {
  final String providerId;
  final Map<String, dynamic> workingHoursRaw;

  const _HeuristicOppPreviewList({
    required this.providerId,
    required this.workingHoursRaw,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 28));
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    final hasWhFilter = workingHoursRaw.isNotEmpty;
    final availability = _HighOppDrilldownList._parseWorkingHours(workingHoursRaw);

    bool allow(DateTime dt) {
      if (!hasWhFilter) return true;
      final allowed = availability[dt.weekday] ?? const <int>[];
      return allowed.contains(dt.hour);
    }

    final q = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(minHeight: 3),
          );
        }

        final counts = <int, int>{}; // key = weekday*100 + hour

        for (final d in snap.data!.docs) {
          final ts = d.data()['scheduledAt'];
          if (ts is! Timestamp) continue;

          final dt = ts.toDate().toLocal();
          if (!allow(dt)) continue;

          final key = _howKey(dt.weekday, dt.hour);
          counts[key] = (counts[key] ?? 0) + 1;
        }

        if (counts.isEmpty) {
          return Text(
            hasWhFilter
                ? "Not enough data yet within your Working Hours. Complete more bookings to generate insights."
                : "Not enough data yet. Complete more bookings to generate insights.",
            style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
          );
        }

        // Build best hour per day for next 7 days, then take top 3 days
        final now2 = DateTime.now();
        final day0 = DateTime(now2.year, now2.month, now2.day);

        final dayCandidates = <({DateTime day, int hour, int count})>[];

        for (int i = 0; i < 7; i++) {
          final d = day0.add(Duration(days: i));
          final wd = d.weekday;

          final allowedHours = hasWhFilter
              ? (availability[wd] ?? const <int>[])
              : List.generate(24, (h) => h);

          if (allowedHours.isEmpty) continue; // closed day

          int bestHour = allowedHours.first;
          int bestCount = counts[_howKey(wd, bestHour)] ?? 0;

          for (final h in allowedHours) {
            final c = counts[_howKey(wd, h)] ?? 0;
            if (c > bestCount) {
              bestCount = c;
              bestHour = h;
            }
          }

          dayCandidates.add((day: d, hour: bestHour, count: bestCount));
        }

        if (dayCandidates.isEmpty) {
          return const Text(
            "Closed (Working Hours disabled).",
            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
          );
        }

        dayCandidates.sort((a, b) {
          final s = b.count.compareTo(a.count);
          if (s != 0) return s;
          return a.day.compareTo(b.day); // tie-break by earliest day
        });

        final top3 = dayCandidates.take(3).toList();

        return Column(
          children: top3.map((e) {
            final dt = e.day;
            final label = "${_wdShort(dt.weekday)} ${dt.day}/${dt.month} • ${_fmtHour(e.hour)}";
            final badge = (e.count == 0) ? "Available" : "${e.count} bookings";

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: KLPalette.tint50,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: KLPalette.primary700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  static int _howKey(int weekday1to7, int hour0to23) => weekday1to7 * 100 + hour0to23;
  static int _howWeekday(int key) => key ~/ 100;
  static int _howHour(int key) => key % 100;

  static String _fmtHour(int h) => "${h.toString().padLeft(2, '0')}:00";

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

class ProviderHighOpportunityScreen extends StatelessWidget {
  final String providerId;
  const ProviderHighOpportunityScreen({super.key, required this.providerId});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 28));
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    final bookingsQ = FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: providerId)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end));

    final workingHoursDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(providerId);

    final userDoc = FirebaseFirestore.instance.collection('users').doc(providerId);

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
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
                  const Text(
                    "High-Opportunity Hours",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 14),

              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userDoc.snapshots(),
                  builder: (context, userSnap) {
                    if (!userSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final userData = userSnap.data?.data() ?? const <String, dynamic>{};

                    // --- AI slots (users/{uid}.opportunity_index.slots) ---
                    final opp = userData['opportunity_index'];
                    final oppMap = (opp is Map) ? Map<String, dynamic>.from(opp as Map) : null;

                    final algo = oppMap?['algo']?.toString();
                    final updatedAt = oppMap?['updatedAt'];
                    final updatedTs = (updatedAt is Timestamp) ? updatedAt : null;

                    final slotsRaw = oppMap?['slots'];
                    final slots = (slotsRaw is List)
                        ? slotsRaw
                        .whereType<Map>()
                        .map((m) => Map<String, dynamic>.from(m))
                        .toList()
                        : <Map<String, dynamic>>[];

                    // Working hours fallback
                    final whFallback = (userData['workingHours'] is Map)
                        ? (userData['workingHours'] as Map).cast<String, dynamic>()
                        : <String, dynamic>{};

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: workingHoursDoc.snapshots(),
                      builder: (context, whSnap) {
                        final hasWhDoc = whSnap.data?.exists == true;

                        final whField = whSnap.data?.data()?['workingHours'];
                        final workingHoursRaw = (whField is Map)
                            ? Map<String, dynamic>.from(whField)
                            : whFallback;

                        if (slots.isNotEmpty) {
                          return _AiHighOppDrilldownList(
                            slotsRaw: slots,
                            workingHoursRaw: workingHoursRaw,
                            algo: algo,
                            updatedAt: updatedTs,
                          );
                        }

                        // Fallback path (heuristic)
                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: bookingsQ.snapshots(),
                          builder: (context, bookingsSnap) {
                            if (!bookingsSnap.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final counts = <int, int>{};
                            for (final d in bookingsSnap.data!.docs) {
                              final ts = d.data()['scheduledAt'];
                              if (ts is Timestamp) {
                                final dt = ts.toDate().toLocal();
                                final key = dt.weekday * 100 + dt.hour;
                                counts[key] = (counts[key] ?? 0) + 1;
                              }
                            }

                            return _HighOppDrilldownList(
                              countsByHow: counts,
                              workingHoursRaw: workingHoursRaw,
                              showFallbackNote: true,
                            );
                          },
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
}

class _HighOppDrilldownList extends StatelessWidget {
  final Map<int, int> countsByHow; // key = weekday*100 + hour
  final Map<String, dynamic> workingHoursRaw;
  final bool showFallbackNote;

  const _HighOppDrilldownList({
    required this.countsByHow,
    required this.workingHoursRaw,
    this.showFallbackNote = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(
      7,
          (i) => DateTime(now.year, now.month, now.day).add(Duration(days: i)),
    );

    final availability = _parseWorkingHours(workingHoursRaw);
    final hasWhFilter = workingHoursRaw.isNotEmpty;

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: days.length + (showFallbackNote ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (showFallbackNote && i == 0) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KLPalette.tint50,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: KLPalette.border),
              ),
              child: const Text(
                "AI forecast not available yet (needs enough booking history). Showing heuristic based on past booking frequency.",
                style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
              ),
            ),
          );
        }

        final dayIndex = showFallbackNote ? (i - 1) : i;
        final day = days[dayIndex];
        final wd = day.weekday; // 1..7


        final hours = hasWhFilter
            ? (availability[wd] ?? const <int>[])
            : List.generate(24, (h) => h);

        final ranked = hours
            .map((h) => MapEntry(h, countsByHow[wd * 100 + h] ?? 0))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final show = ranked.take(6).toList();

        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KLPalette.bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: KLPalette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmtDayHeader(day),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 10),

                if (hours.isEmpty)
                  const Text(
                    "Closed (Working Hours disabled).",
                    style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: show.map((e) {
                      final h = e.key;
                      final c = e.value;

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
                              "${h.toString().padLeft(2, '0')}:00",
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: KLPalette.primary700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              c == 0 ? "Available" : "$c hist.",
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 10),
                const Text(
                  "Heuristic: ranked by past booking frequency, filtered by working hours when available.",
                  style: TextStyle(
                    color: KLPalette.text2,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fmtDayHeader(DateTime d) {
    const wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return "${wd[d.weekday - 1]} • ${d.day}/${d.month}/${d.year}";
  }

  /// Returns map: weekday(1..7) -> list of allowed hours(0..23)
  static Map<int, List<int>> _parseWorkingHours(Map<String, dynamic> raw) {
    if (raw.isEmpty) return {};

    // Format A: { "days": [ { "weekday": 1, "startHour": 9, "endHour": 17, "enabled": true }, ... ] }
    final days = raw['days'];
    if (days is List) {
      final out = <int, List<int>>{};
      for (final x in days) {
        if (x is Map) {
          final wd = (x['weekday'] as num?)?.toInt();
          final enabled = (x['enabled'] ?? true) == true;
          final startH = (x['startHour'] as num?)?.toInt();
          final endH = (x['endHour'] as num?)?.toInt();
          if (wd != null && enabled && startH != null && endH != null) {
            final hrs = <int>[];
            for (int h = startH; h < endH; h++) {
              if (h >= 0 && h <= 23) hrs.add(h);
            }
            if (hrs.isNotEmpty) out[wd] = hrs;
          }
        }
      }
      if (out.isNotEmpty) return out;
    }

    // Format B: { "mon": { "start": "09:00", "end": "18:00", "enabled": true }, ... }
    final out2 = <int, List<int>>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().toLowerCase();

      final wd = switch (key) {
        'mon' => 1,
        'tue' => 2,
        'wed' => 3,
        'thu' => 4,
        'fri' => 5,
        'sat' => 6,
        'sun' => 7,
        _ => null,
      };
      if (wd == null) continue;

      final v = entry.value;
      if (v is! Map) continue;

      final enabled = (v['enabled'] ?? true) == true;
      if (!enabled) continue;

      final startStr = v['start']?.toString();
      final endStr = v['end']?.toString();
      if (startStr == null || endStr == null) continue;

      int? toMinutes(String s) {
        final p = s.split(':');
        if (p.length != 2) return null;
        final h = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        if (h == null || m == null) return null;
        return h * 60 + m;
      }

      final startMin = toMinutes(startStr);
      final endMin = toMinutes(endStr);
      if (startMin == null || endMin == null) continue;

      final firstHour = ((startMin + 59) ~/ 60); // ceil
      final lastHourExclusive = (endMin ~/ 60); // floor

      final hrs = <int>[];
      for (int h = firstHour; h < lastHourExclusive; h++) {
        if (h >= 0 && h <= 23) hrs.add(h);
      }

      if (hrs.isNotEmpty) out2[wd] = hrs;
    }
    return out2;
  }
}

/// --- Drilldown list  ---
class _OppSlot {
  final DateTime startAtLocal;
  final double score;
  final double? expectedRevenue;
  final double? expectedBookings;
  final double? expectedViews;
  final double? expectedConversionRate;

  const _OppSlot({
    required this.startAtLocal,
    required this.score,
    this.expectedRevenue,
    this.expectedBookings,
    this.expectedViews,
    this.expectedConversionRate,
  });
}


class _AiHighOppDrilldownList extends StatelessWidget {
  final List<Map<String, dynamic>> slotsRaw;
  final Map<String, dynamic> workingHoursRaw;
  final String? algo;
  final Timestamp? updatedAt;

  const _AiHighOppDrilldownList({
    required this.slotsRaw,
    required this.workingHoursRaw,
    this.algo,
    this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final slots = _parseSlots(slotsRaw);

    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
    final dayEnd = day0.add(const Duration(days: 7));

    // Only keep next 7 days
    final horizon = slots.where((s) {
      return s.startAtLocal.isAfter(day0.subtract(const Duration(seconds: 1))) &&
          s.startAtLocal.isBefore(dayEnd);
    }).toList();

    // Group by day
    final byDay = <DateTime, List<_OppSlot>>{};
    for (final s in horizon) {
      final k = DateTime(s.startAtLocal.year, s.startAtLocal.month, s.startAtLocal.day);
      (byDay[k] ??= <_OppSlot>[]).add(s);
    }

    final availability = _HighOppDrilldownList._parseWorkingHours(workingHoursRaw);
    final hasWhFilter = workingHoursRaw.isNotEmpty;

    final days = List.generate(7, (i) => day0.add(Duration(days: i)));

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: days.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        // header info card
        if (i == 0) {
          final algoLabel = (algo == null || algo!.trim().isEmpty) ? "AI" : "AI";
          final updatedLabel = updatedAt == null ? "" : " • Updated ${_fmtShort(updatedAt!.toDate().toLocal())}";
          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KLPalette.tint50,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: KLPalette.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      "$algoLabel forecast recommends peak hours (next 7 days).\n"
                          "Scores are normalized 0–100\n$updatedLabel\n"
                          "Est. RM = predicted revenue for new bookings during that hour.",
                      style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showOppHelp(context),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.info_outline_rounded, size: 20, color: KLPalette.text2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final day = days[i - 1];
        final wd = day.weekday;

        final allowedHours = hasWhFilter
            ? (availability[wd] ?? const <int>[]) // missing day => closed
            : List.generate(24, (h) => h);

        final dayKey = DateTime(day.year, day.month, day.day);
        double metric(_OppSlot s) => (s.expectedRevenue ?? s.score);

        final all = (byDay[dayKey] ?? <_OppSlot>[]);
        final inWhSlots = hasWhFilter
            ? all.where((s) => allowedHours.contains(s.startAtLocal.hour)).toList()
            : all.toList();

        final outWhSlots = hasWhFilter
            ? all.where((s) => !allowedHours.contains(s.startAtLocal.hour)).toList()
            : <_OppSlot>[];

        inWhSlots.sort((a, b) => metric(b).compareTo(metric(a)));
        outWhSlots.sort((a, b) => metric(b).compareTo(metric(a)));

        final chips = <_ChipItem>[];
        final usedHours = <int>{};

        // Prefer in-WH AI slots first
        for (final s in inWhSlots.take(6)) {
          final h = s.startAtLocal.hour;
          usedHours.add(h);

          final rev = s.expectedRevenue;
          final label = (rev != null)
              ? "Est. RM ${rev.toStringAsFixed(0)}"
              : "Score ${s.score.toStringAsFixed(0)}";

          chips.add(_ChipItem(hour: h, label: label, isAi: true, outsideWh: false, slot: s));
        }

        // Fill remaining with out-of-WH AI recommendations (open suggestion)
        if (chips.length < 6) {
          for (final s in outWhSlots) {
            if (chips.length >= 6) break;

            final h = s.startAtLocal.hour;
            if (usedHours.contains(h)) continue;
            usedHours.add(h);

            final rev = s.expectedRevenue;
            final label = (rev != null)
                ? "Est. RM ${rev.toStringAsFixed(0)}"
                : "Score ${s.score.toStringAsFixed(0)}";

            chips.add(_ChipItem(hour: h, label: label, isAi: true, outsideWh: true, slot: s));
          }
        }

        // Fill remaining with non-AI available hours (only if the day is open)
        if (chips.length < 6 && allowedHours.isNotEmpty) {
          for (final h in allowedHours) {
            if (chips.length >= 6) break;
            if (usedHours.contains(h)) continue;
            chips.add(_ChipItem(hour: h, label: "Available", isAi: false));
          }
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KLPalette.bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: KLPalette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmtDayHeader(day),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 10),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    if (allowedHours.isEmpty)
                      const Text(
                        "Working hours are disabled for this day.\n",
                        style: TextStyle(
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                    if (chips.isEmpty)
                      const Text(
                        "No AI suggestions for this day yet.",
                        style: TextStyle(
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: chips.map((c) {
                        final outsideBg = const Color(0xFFFFFBEB);
                        final outsideText = const Color(0xFFB45309);

                        final bg = c.outsideWh ? outsideBg : KLPalette.tint50;
                        final timeColor =
                        c.outsideWh ? outsideText : KLPalette.primary700;
                        final labelColor =
                        c.outsideWh ? outsideText : KLPalette.text;

                        Widget chipBody = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: KLPalette.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${c.hour.toString().padLeft(2, '0')}:00",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: timeColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                c.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: labelColor,
                                ),
                              ),
                            ],
                          ),
                        );

                        if (!c.isAi || c.slot == null) return chipBody;

                        return InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => _showSlotDetails(context, c.slot!),
                          child: chipBody,
                        );
                      }).toList(),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                const Text(
                  "Chip value shows estimated revenue for that hour (Est. RM). Tap an AI chip for details.\n"
                      "Non-AI chips are simply your available hours.\n"
                      "Highlighted chips are strong opportunities outside your Working Hours — consider updating Working Hours to open then.",
                  style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static double? _d(dynamic v) => (v is num) ? v.toDouble() : null;

  static List<_OppSlot> _parseSlots(List<Map<String, dynamic>> raw) {
    final out = <_OppSlot>[];
    for (final m in raw) {
      final ts = m['startAt'];
      DateTime? dt;
      if (ts is Timestamp) dt = ts.toDate();
      if (ts is DateTime) dt = ts;

      final score = _d(m['score']) ?? 0;

      if (dt != null) {
        out.add(
          _OppSlot(
            startAtLocal: dt.toLocal(),
            score: score,
            expectedRevenue: _d(m['expectedRevenue']),
            expectedBookings: _d(m['expectedBookings']),
            expectedViews: _d(m['expectedViews']),
            expectedConversionRate: _d(m['expectedConversionRate']),
          ),
        );
      }
    }
    return out;
  }

  static void _showSlotDetails(BuildContext context, _OppSlot s) {
    String rm0(double? v) => (v == null) ? "-" : "RM ${v.toStringAsFixed(0)}";
    String rm2(double? v) => (v == null) ? "-" : "RM ${v.toStringAsFixed(2)}";
    String num2(double? v) => (v == null) ? "-" : v.toStringAsFixed(2);
    String views0(double? v) => (v == null) ? "-" : v.toStringAsFixed(0);

    final start = s.startAtLocal;
    final end = start.add(const Duration(hours: 1));
    final when =
        "${_fmtDay(start)} • ${_fmtHm(start)}–${_fmtHm(end)}";

    // Only show conversion if views exist & > 0 (prevents confusing “infinite”/clipped cases)
    final v = s.expectedViews;
    final conv = (s.expectedConversionRate != null && v != null && v > 0)
        ? "${(s.expectedConversionRate! * 100).toStringAsFixed(2)}%"
        : "N/A";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                const SizedBox(height: 6),
                Text(
                  when,
                  style: const TextStyle(
                    color: KLPalette.text2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),

                _metricRow(
                  "Estimated revenue (Est. RM)",
                  rm2(s.expectedRevenue),
                  "Forecasted gross revenue from new bookings in this hour. "
                      "Use as a planning guide (not guaranteed).",
                ),
                _metricRow(
                  "Expected bookings",
                  num2(s.expectedBookings),
                  "Average bookings predicted for this hour. "
                      "Example: 0.35 ≈ ~35% chance of 1 booking (or 1 booking every ~3 similar hours).",
                ),
                _metricRow(
                  "Expected views",
                  "${views0(s.expectedViews)}",
                  "Estimated number of people viewing your service/profile during this hour. "
                      "If this is 0 or missing, conversion may show as N/A.",
                ),
                _metricRow(
                  "Expected conversion",
                  conv,
                  "Estimated bookings ÷ views for this hour. "
                      "Shown only when views are available (> 0).",
                ),

                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KLPalette.tint50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: const Text(
                      "Tip: Choose higher Est. RM slots to maximize your earnings.\n"
                          "If Working Hours filters out slots, AI only ranks the hours you’re actually open.",
                      style: TextStyle(
                        color: KLPalette.text2,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _metricRow(String k, String v, String help) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900))),
              Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            help,
            style: const TextStyle(
              color: KLPalette.text2,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDay(DateTime d) {
    const wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return "${wd[d.weekday - 1]} $dd/$mm/${d.year}";
  }

  static String _fmtHm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return "$hh:$mi";
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

  static String _fmtDayHeader(DateTime d) {
    const wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return "${wd[d.weekday - 1]} • ${d.day}/${d.month}/${d.year}";
  }

  static String _fmtShort(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return "$dd/$mm $hh:$mi";
  }

  static void _showOppHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("About High-Opportunity Hours",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                SizedBox(height: 10),

                Text("What chip labels mean",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text("• Est. RM: predicted revenue from new bookings during that hour.\n"
                    "• Score: relative demand score (0–100) when revenue isn’t available.\n"
                    "• Available: you’re open then, but AI didn’t rank it in the top slots.",
                    style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),

                SizedBox(height: 12),
                Text("Tip",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text("Use Est. RM to plan your availability, promos, and staffing. "
                    "These are forecasts (not guarantees).",
                    style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );
      },
    );
  }

}

class _ChipItem {
  final int hour;
  final String label;
  final bool isAi;
  final bool outsideWh;
  final _OppSlot? slot;

  const _ChipItem({
    required this.hour,
    required this.label,
    required this.isAi,
    this.outsideWh = false,
    this.slot,
  });
}

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String _fmtRmCompact(double v) {
  // RM 0, RM 999, RM 1.2k, RM 3.4M
  final n = v.isFinite ? v : 0.0;
  final abs = n.abs();

  String fmt(double x, {int dp = 1}) {
    final s = x.toStringAsFixed(dp);
    // trim trailing .0
    if (s.endsWith('.0')) return s.substring(0, s.length - 2);
    return s;
  }

  if (abs >= 1000000) return "RM ${fmt(n / 1000000)}M";
  if (abs >= 1000) return "RM ${fmt(n / 1000)}k";
  return "RM ${n.toStringAsFixed(0)}";
}

String? _coverUrlFromProviderServiceUi(ProviderServiceUi s) {
  final d = s as dynamic;

  String? pickString(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  // Common direct fields
  try { final v = d.thumbnailUrl; final r = pickString(v); if (r != null) return r; } catch (_) {}
  try { final v = d.coverUrl;     final r = pickString(v); if (r != null) return r; } catch (_) {}
  try { final v = d.imageUrl;     final r = pickString(v); if (r != null) return r; } catch (_) {}

  // photoUrls / photos list
  try {
    final v = d.photoUrls;
    if (v is List && v.isNotEmpty && v.first is String) return (v.first as String).trim();
  } catch (_) {}
  try {
    final v = d.photos;
    if (v is List && v.isNotEmpty && v.first is String) return (v.first as String).trim();
  } catch (_) {}

  // images list (string or map)
  try {
    final v = d.images;
    if (v is List && v.isNotEmpty) {
      final first = v.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
      if (first is Map) {
        final url = first['url'] ?? first['downloadUrl'] ?? first['thumbnailUrl'];
        if (url is String && url.trim().isNotEmpty) return url.trim();
      }
    }
  } catch (_) {}

  return null;
}

class _NetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final IconData placeholderIcon;

  const _NetImage({
    this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholderIcon = Icons.image,
  });

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();

    Widget placeholder() => Container(
      width: width,
      height: height,
      color: KLPalette.mutedBg,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, size: 44, color: KLPalette.text2),
    );

    if (u.isEmpty) return placeholder();

    return Image.network(
      u,
      width: width,
      height: height,
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

class _ServiceCoverImage extends StatelessWidget {
  final ProviderServiceUi s;
  const _ServiceCoverImage({required this.s});

  @override
  Widget build(BuildContext context) {
    final url = _coverUrlFromProviderServiceUi(s);
    final fallbackAsset = _defaultAssetForCategory(s.category);

    if (url == null || url.trim().isEmpty) {
      return Image.asset(fallbackAsset, fit: BoxFit.cover);
    }

    return Image.network(
      url.trim(),
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: KLPalette.mutedBg,
          alignment: Alignment.center,
          child: const Icon(Icons.image, color: KLPalette.text2, size: 42),
        );
      },
      errorBuilder: (_, __, ___) =>
          Image.asset(fallbackAsset, fit: BoxFit.cover),
    );
  }
}