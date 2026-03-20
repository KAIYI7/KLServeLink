import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/core/widgets/service_thumb.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/utils/app_snack.dart';
import '../data/booking_firestore.dart';
import '../models/provider_booking_model.dart';
import 'provider_booking_details_screen.dart';

class ProviderBookingsTab extends StatefulWidget {
  const ProviderBookingsTab({super.key});

  @override
  State<ProviderBookingsTab> createState() => _ProviderBookingsTabState();
}

class _ProviderBookingsTabState extends State<ProviderBookingsTab> {
  final api = BookingFirestore();

  ProviderBookingStatus filter = ProviderBookingStatus.all;

  bool showSearch = false;
  final searchCtrl = TextEditingController();
  String _q = "";

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      showSearch = !showSearch;
      if (!showSearch) {
        searchCtrl.clear();
        _q = "";
      }
    });
  }

  void _showSortInfo(BuildContext context) {
    String title;
    List<String> lines;

    switch (filter) {
      case ProviderBookingStatus.pending:
        title = "Sorting (Pending)";
        lines = [
          "Newest booking requests first.",
          "Uses created/request time when available.",
        ];
        break;

      case ProviderBookingStatus.accepted:
      case ProviderBookingStatus.confirmed:
        title = "Sorting (Accepted / Confirmed)";
        lines = [
          "Next scheduled job first (soonest first).",
        ];
        break;

      case ProviderBookingStatus.completed:
        title = "Sorting (Completed)";
        lines = [
          "Newest completed jobs first.",
        ];
        break;

      case ProviderBookingStatus.declined:
      case ProviderBookingStatus.cancelled:
        title = "Sorting (Declined / Cancelled)";
        lines = [
          "Most recent updates first (latest decision first).",
        ];
        break;

      case ProviderBookingStatus.all:
      default:
        title = "Sorting (All)";
        lines = [
          "Grouped by priority:",
          "• Pending first (newest request first)",
          "• Accepted/Confirmed next (soonest schedule first)",
          "• Completed next (newest first)",
          "• Declined/Cancelled last (newest update first)",
        ];
        break;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KLPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.sort, color: KLPalette.text2),
                  const SizedBox(width: 10),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 12),
              for (final t in lines) ...[
                Text(
                  t,
                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<ProviderBooking> _applySearch(List<ProviderBooking> items) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return items;

    bool match(ProviderBooking b) {
      final id = b.id.toLowerCase();
      final service = b.serviceName.toLowerCase();
      final seeker = b.seekerName.toLowerCase();
      final loc = b.locationText.toLowerCase();
      return id.contains(q) || service.contains(q) || seeker.contains(q) || loc.contains(q);
    }

    return items.where(match).toList();
  }

  DateTime _safeCreatedAt(ProviderBooking b) {
    final d = b as dynamic;

    try {
      final v = d.createdAt;
      if (v is DateTime) return v;
    } catch (_) {}

    try {
      final v = d.created;
      if (v is DateTime) return v;
    } catch (_) {}

    try {
      final v = d.requestedAt;
      if (v is DateTime) return v;
    } catch (_) {}

    // Fallback: scheduledAt
    return b.scheduledAt;
  }

  DateTime _safeUpdatedAt(ProviderBooking b) {
    final d = b as dynamic;

    try {
      final v = d.updatedAt;
      if (v is DateTime) return v;
    } catch (_) {}

    try {
      final v = d.declinedAt;
      if (v is DateTime) return v;
    } catch (_) {}

    try {
      final v = d.cancelledAt;
      if (v is DateTime) return v;
    } catch (_) {}

    try {
      final v = d.completedAt;
      if (v is DateTime) return v;
    } catch (_) {}

    // Fallback
    return b.scheduledAt;
  }

  int _rankStatus(ProviderBookingStatus s) {
    // group priority in "All"
    switch (s) {
      case ProviderBookingStatus.pending:
        return 0;
      case ProviderBookingStatus.accepted:
      case ProviderBookingStatus.confirmed:
        return 1;
      case ProviderBookingStatus.completed:
        return 2;
      case ProviderBookingStatus.declined:
      case ProviderBookingStatus.cancelled:
        return 3;
      case ProviderBookingStatus.all:
      default:
        return 99;
    }
  }

  int _compareProviderBookings(ProviderBooking a, ProviderBooking b) {
    // If a specific filter is selected, apply that filter-specific ordering:
    if (filter == ProviderBookingStatus.pending) {
      // newest request first
      return _safeCreatedAt(b).compareTo(_safeCreatedAt(a));
    }

    if (filter == ProviderBookingStatus.accepted || filter == ProviderBookingStatus.confirmed) {
      // next job first
      return a.scheduledAt.compareTo(b.scheduledAt);
    }

    if (filter == ProviderBookingStatus.completed) {
      // newest completed first
      return b.scheduledAt.compareTo(a.scheduledAt);
    }

    if (filter == ProviderBookingStatus.declined || filter == ProviderBookingStatus.cancelled) {
      // most recent decision first
      final c = _safeUpdatedAt(b).compareTo(_safeUpdatedAt(a));
      if (c != 0) return c;
      return b.scheduledAt.compareTo(a.scheduledAt);
    }

    // "All": group ordering + within-group ordering
    final ra = _rankStatus(a.status);
    final rb = _rankStatus(b.status);
    if (ra != rb) return ra.compareTo(rb);

    // Within same group:
    if (ra == 0) {
      // pending
      return _safeCreatedAt(b).compareTo(_safeCreatedAt(a));
    } else if (ra == 1) {
      // accepted/confirmed
      return a.scheduledAt.compareTo(b.scheduledAt);
    } else {
      // completed / declined / cancelled
      final c = _safeUpdatedAt(b).compareTo(_safeUpdatedAt(a));
      if (c != 0) return c;
      return b.scheduledAt.compareTo(a.scheduledAt);
    }
  }

  Map<String, dynamic> _paymentMap(Map<String, dynamic> d) {
    final p = d["payment"];
    if (p is Map) return Map<String, dynamic>.from(p as Map);
    return <String, dynamic>{};
  }

  String _paymentMethodFromBooking(Map<String, dynamic> b) {
    final p = _paymentMap(b);
    return (p['method'] ?? b['paymentMethod'] ?? '').toString().toLowerCase();
  }

  String _paymentStateFromBooking(Map<String, dynamic> b) {
    final p = _paymentMap(b);
    return (p['state'] ?? '').toString().toLowerCase();
  }

  bool _cardPaidOrCaptured(Map<String, dynamic> b) {
    final method = _paymentMethodFromBooking(b);
    final state = _paymentStateFromBooking(b);
    return method == 'card' && (state == 'authorized' || state == 'captured');
  }

  DateTime? _validCompletionTime(ProviderBooking b, Map<String, dynamic> raw) {
    final scheduledAt = b.scheduledAt;

    final hoursRaw = raw['hours'];
    final hours = (hoursRaw is num) ? hoursRaw.toDouble() : 0.0;
    if (hours <= 0) return null;

    final totalMinutes = (hours * 60).round();
    return scheduledAt.add(Duration(minutes: totalMinutes));
  }

  Future<Map<String, dynamic>?> _fetchBookingRaw(String bookingId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .get();

      if (!snap.exists) {
        if (!mounted) return null;
        AppSnack.show(
          context,
          "Booking not found.",
          type: AppSnackType.error,
        );
        return null;
      }

      return snap.data() ?? <String, dynamic>{};
    } catch (e) {
      if (!mounted) return null;
      AppSnack.show(
        context,
        "Failed to load booking.",
        type: AppSnackType.error,
      );
      return null;
    }
  }

  Future<void> _providerDeclineOrCancel({
    required Map<String, dynamic> bookingData,
    required String bookingId,
  }) async {
    try {
      if (_cardPaidOrCaptured(bookingData)) {
        final callable =
        FirebaseFunctions.instance.httpsCallable('cancelBookingWithRefund');

        await callable.call({
          'bookingId': bookingId,
          'reason': 'provider_declined',
        });

        if (!mounted) return;
        AppSnack.show(
          context,
          "Declined + refund processed.",
          type: AppSnackType.success,
        );
      } else {
        await _updateById(bookingId, ProviderBookingStatus.declined);

        if (!mounted) return;
        AppSnack.show(
          context,
          "Booking declined.",
          type: AppSnackType.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        "Decline failed: $e",
        type: AppSnackType.error,
      );
    }
  }

  Future<void> _handleDecline(ProviderBooking b) async {
    final raw = await _fetchBookingRaw(b.id);
    if (raw == null) return;

    await _providerDeclineOrCancel(
      bookingData: raw,
      bookingId: b.id,
    );
  }

  Future<void> _tryMarkCompleted(ProviderBooking b) async {
    final raw = await _fetchBookingRaw(b.id);
    if (raw == null) return;

    final validAt = _validCompletionTime(b, raw);
    if (validAt != null && DateTime.now().isBefore(validAt)) {
      final hh = validAt.hour.toString().padLeft(2, '0');
      final mm = validAt.minute.toString().padLeft(2, '0');

      final now = DateTime.now();
      final sameDay =
          now.year == validAt.year &&
              now.month == validAt.month &&
              now.day == validAt.day;

      final dateText = "${validAt.day}/${validAt.month}/${validAt.year}";

      if (!mounted) return;
      AppSnack.show(
        context,
        sameDay
            ? "You can only mark this booking completed after $hh:$mm."
            : "You can only mark this booking completed after $dateText $hh:$mm.",
        type: AppSnackType.error,
      );
      return;
    }

    await _update(b, ProviderBookingStatus.completed);
  }

  Future<void> _updateById(String bookingId, ProviderBookingStatus newStatus) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await api.updateStatus(
        bookingId: bookingId,
        newStatus: newStatus,
        actorUid: uid,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        "Update failed: $e",
        type: AppSnackType.error,
      );
    }
  }

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
              // Top bar
              Row(
                children: [
                  const _CircleBrand(),
                  const Spacer(),
                  const Text("Bookings", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  const Spacer(),
                  Row(
                    children: [
                      _CircleButton(
                        icon: showSearch ? Icons.close_rounded : Icons.search,
                        onTap: _toggleSearch,
                      ),
                      const SizedBox(width: 10),
                      _CircleButton(
                        icon: Icons.info_outline_rounded,
                        onTap: () => _showSortInfo(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              _Segmented(
                value: filter,
                onChanged: (v) => setState(() => filter = v),
              ),

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  filter == ProviderBookingStatus.pending
                      ? "Sorted: newest request first"
                      : (filter == ProviderBookingStatus.accepted || filter == ProviderBookingStatus.confirmed)
                      ? "Sorted: next scheduled job first"
                      : (filter == ProviderBookingStatus.completed)
                      ? "Sorted: newest completed first"
                      : (filter == ProviderBookingStatus.declined || filter == ProviderBookingStatus.cancelled)
                      ? "Sorted: latest update first"
                      : "Sorted: Pending → Accepted/Confirmed → Completed → Declined/Cancelled",
                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                ),
              ),

              if (showSearch) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  onChanged: (v) => setState(() => _q = v),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: "Search by service / seeker / booking ID / location",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: KLPalette.mutedBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: KLPalette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: KLPalette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: KLPalette.primary, width: 2),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              Expanded(
                child: (uid == null)
                    ? const Center(child: Text("Please login"))
                    : StreamBuilder<List<ProviderBooking>>(
                  stream: api.streamProviderBookings(
                    providerId: uid,
                    filter: filter,
                  ),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text("Error: ${snap.error}"));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final raw = snap.data ?? const [];
                    final items = _applySearch(raw)..sort(_compareProviderBookings);

                    if (items.isEmpty) {
                      // If searching, show a nicer empty message
                      if (_q.trim().isNotEmpty) {
                        return const Center(
                          child: Text(
                            "No results found.",
                            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                          ),
                        );
                      }
                      return _Empty(filter: filter);
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final b = items[i];
                        return _BookingCard(
                          b: b,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProviderBookingDetailsScreen(bookingId: b.id),
                              ),
                            );
                          },
                          onAccept: b.status == ProviderBookingStatus.pending
                              ? () => _update(b, ProviderBookingStatus.accepted)
                              : null,
                          onDecline: b.status == ProviderBookingStatus.pending
                              ? () => _handleDecline(b)
                              : null,
                          onComplete: (b.status == ProviderBookingStatus.accepted ||
                              b.status == ProviderBookingStatus.confirmed)
                              ? () => _tryMarkCompleted(b)
                              : null,
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

  Future<void> _update(ProviderBooking b, ProviderBookingStatus newStatus) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await api.updateStatus(
        bookingId: b.id,
        newStatus: newStatus,
        actorUid: uid,
      );

      if (!mounted) return;
      AppSnack.show(
        context,
        "Status updated to ${bookingStatusToString(newStatus)}",
        type: AppSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        "Update failed: $e",
        type: AppSnackType.error,
      );
    }
  }
}

class _Segmented extends StatelessWidget {
  final ProviderBookingStatus value;
  final ValueChanged<ProviderBookingStatus> onChanged;

  const _Segmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, ProviderBookingStatus v) {
      final selected = v == value;

      return InkWell(
        onTap: () => onChanged(v),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(
            minWidth: 72,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? KLPalette.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : KLPalette.text,
            ),
          ),
        ),
      );
    }

    final statuses = [
      ProviderBookingStatus.all,
      ProviderBookingStatus.pending,
      ProviderBookingStatus.accepted,
      ProviderBookingStatus.confirmed,
      ProviderBookingStatus.completed,
      ProviderBookingStatus.declined,
    ];

    final labels = [
      "All",
      "Pending",
      "Accepted",
      "Confirmed",
      "Completed",
      "Declined",
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: KLPalette.border.withOpacity(0.6),
          ),
        ),
        child: Stack(
          children: [
            ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              physics: const BouncingScrollPhysics(),
              itemCount: labels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return chip(labels[index], statuses[index]);
              },
            ),

            // Right fade to indicate scroll
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        KLPalette.bg.withOpacity(0),
                        KLPalette.bg,
                      ],
                    ),
                  ),
                ),
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

class _Empty extends StatelessWidget {
  final ProviderBookingStatus filter;
  const _Empty({required this.filter});

  @override
  Widget build(BuildContext context) {
    final msg = switch (filter) {
      ProviderBookingStatus.all => "No bookings yet.",
      ProviderBookingStatus.pending => "No pending bookings yet.",
      ProviderBookingStatus.accepted => "No accepted bookings yet.",
      ProviderBookingStatus.confirmed => "No confirmed bookings yet.",
      ProviderBookingStatus.completed => "No completed bookings yet.",
      ProviderBookingStatus.declined => "No declined bookings yet.",
      ProviderBookingStatus.cancelled => "No cancelled bookings yet.",
      _ => "No bookings.",
    };

    return Center(
      child: Text(msg, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final ProviderBooking b;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onComplete;

  const _BookingCard({
    required this.b,
    required this.onTap,
    required this.onAccept,
    required this.onDecline,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final status = b.status;

    Color pillBg;
    Color pillFg;
    String pillText;

    switch (status) {
      case ProviderBookingStatus.all:
        pillBg = KLPalette.mutedBg;
        pillFg = KLPalette.text2;
        pillText = "—";
        break;
      case ProviderBookingStatus.pending:
        pillBg = const Color(0xFFFFEEF0);
        pillFg = const Color(0xFFB91C1C);
        pillText = "Pending";
        break;
      case ProviderBookingStatus.accepted:
        pillBg = KLPalette.tint50;
        pillFg = KLPalette.primary700;
        pillText = "Accepted";
        break;
      case ProviderBookingStatus.confirmed:
        pillBg = KLPalette.tint50;
        pillFg = KLPalette.primary700;
        pillText = "Confirmed";
        break;
      case ProviderBookingStatus.completed:
        pillBg = const Color(0xFFECFDF3);
        pillFg = const Color(0xFF15803D);
        pillText = "Completed";
        break;
      case ProviderBookingStatus.declined:
        pillBg = KLPalette.mutedBg;
        pillFg = KLPalette.text2;
        pillText = "Declined";
        break;
      case ProviderBookingStatus.cancelled:
        pillBg = KLPalette.mutedBg;
        pillFg = KLPalette.text2;
        pillText = "Cancelled";
        break;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: KLPalette.border),
          ),
          child: Column(
            children: [
              // image header
              Container(
                height: 150,
                width: double.infinity,
                color: KLPalette.mutedBg,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _BookingCoverImage(b: b),
                    ),

                    Positioned(
                      left: 14,
                      top: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: KLPalette.border),
                        ),
                        child: Text(pillText, style: TextStyle(color: pillFg, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: KLPalette.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text("#${b.id.substring(0, 5)}",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.serviceName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Text("RM ${b.totalAmount.toStringAsFixed(2)}",
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        const Spacer(),
                        const Icon(Icons.person_outline, size: 18, color: KLPalette.text2),
                        const SizedBox(width: 6),
                        Text(b.seekerName, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800)),
                      ],
                    ),

                    const SizedBox(height: 10),
                    _meta(Icons.place_outlined, b.locationText),
                    const SizedBox(height: 8),
                    _meta(Icons.calendar_month_outlined, _fmtDateTime(b.scheduledAt)),

                    if (onAccept != null || onComplete != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (onAccept != null) ...[
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: FilledButton(
                                  onPressed: onAccept,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  ),
                                  child: const Text("Accept", style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  onPressed: onDecline,
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  ),
                                  child: const Text("Decline", style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ),
                          ] else if (onComplete != null) ...[
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: FilledButton(
                                  onPressed: onComplete,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  ),
                                  child: const Text("Mark Completed", style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _meta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: KLPalette.text2),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700))),
      ],
    );
  }

  static String _fmtDateTime(DateTime dt) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return "${two(dt.day)}/${two(dt.month)}/${dt.year}  ${two(dt.hour)}:${two(dt.minute)}";
  }
}

String _defaultAssetForServiceName(String serviceName) {
  final c = serviceName.toLowerCase().trim();

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

class _BookingCoverImage extends StatelessWidget {
  final ProviderBooking b;

  const _BookingCoverImage({required this.b});

  @override
  Widget build(BuildContext context) {
    return ServiceThumb(
      model: b,
      fit: BoxFit.cover,
    );
  }
}