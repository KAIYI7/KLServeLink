import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../booking_firestore.dart';
import '../provider_booking_model.dart';
import '../provider_booking_details_screen.dart';

class ProviderBookingsTab extends StatefulWidget {
  const ProviderBookingsTab({super.key});

  @override
  State<ProviderBookingsTab> createState() => _ProviderBookingsTabState();
}

class _ProviderBookingsTabState extends State<ProviderBookingsTab> {
  final api = BookingFirestore();
  ProviderBookingStatus filter = ProviderBookingStatus.pending;

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
              // top bar
              Row(
                children: const [
                  SizedBox(width: 48),
                  Spacer(),
                  Text("Bookings", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  Spacer(),
                  SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 14),

              _Segmented(
                value: filter,
                onChanged: (v) => setState(() => filter = v),
              ),
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

                    final items = snap.data!;
                    if (items.isEmpty) return _Empty(filter: filter);

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
                              ? () => _update(b, ProviderBookingStatus.declined)
                              : null,
                          onComplete: b.status == ProviderBookingStatus.accepted
                              ? () => _update(b, ProviderBookingStatus.completed)
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Update failed: $e")),
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
      final selected = value == v;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(v),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? KLPalette.primary : KLPalette.tint50,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: KLPalette.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : KLPalette.primary700,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip("Pending", ProviderBookingStatus.pending),
        const SizedBox(width: 10),
        chip("Accepted", ProviderBookingStatus.accepted),
        const SizedBox(width: 10),
        chip("Completed", ProviderBookingStatus.completed),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final ProviderBookingStatus filter;
  const _Empty({required this.filter});

  @override
  Widget build(BuildContext context) {
    final msg = switch (filter) {
      ProviderBookingStatus.pending => "No pending bookings yet.",
      ProviderBookingStatus.accepted => "No accepted bookings yet.",
      ProviderBookingStatus.completed => "No completed bookings yet.",
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
        pillText = "-";
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
                    const Center(child: Icon(Icons.image, color: KLPalette.text2, size: 44)),
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