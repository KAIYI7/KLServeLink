import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/utils/service_thumb.dart';
import 'theme.dart';
import 'booking_firestore.dart';
import 'provider_booking_model.dart';
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
                  _CircleButton(
                    icon: showSearch ? Icons.close_rounded : Icons.search,
                    onTap: _toggleSearch,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              _Segmented(
                value: filter,
                onChanged: (v) => setState(() => filter = v),
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
                    final items = _applySearch(raw);

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
            chip("All", ProviderBookingStatus.all),
            chip("Pending", ProviderBookingStatus.pending),
            chip("Accepted", ProviderBookingStatus.accepted),
            chip("Completed", ProviderBookingStatus.completed),
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