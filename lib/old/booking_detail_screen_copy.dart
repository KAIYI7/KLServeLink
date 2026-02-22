import 'package:flutter/material.dart';
import '../theme.dart';
import 'booking_store.dart';
import '../seeker_nav_controller.dart';
import '../leave_review_screen.dart';

class BookingDetailScreen extends StatelessWidget {
  final BookingUi booking;
  final BookingStore store;
  final SeekerNavController nav;


  const BookingDetailScreen({super.key, required this.booking, required this.store, required this.nav,});

  @override
  Widget build(BuildContext context) {
    final timeText = _formatBookingTime(booking.scheduledAt);
    final isUpcoming = booking.status == BookingStatus.upcoming;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                KLPalette.tint50,
                KLPalette.bg,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              children: [
                _TopBar(
                  title: "Detail Booking",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 26),

                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _MainCard(
                        booking: booking,
                        timeText: timeText,
                      ),

                      // top circle overlay
                      Positioned(
                        top: -38,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            height: 78,
                            width: 78,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: KLPalette.border),
                            ),
                            child: Center(
                              child: Container(
                                height: 60,
                                width: 60,
                                decoration: BoxDecoration(
                                  color: isUpcoming ? const Color(0xFFFBBF24) : const Color(0xFF80EDC7), // green
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isUpcoming ? Icons.access_time_rounded : Icons.check_rounded,
                                  color: isUpcoming ? Colors.black : Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFE4E6),
                      foregroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: isUpcoming
                        ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Cancel booking (TODO)")),
                      );
                    }
                        : null, // completed -> disabled
                    child: const Text(
                      "Cancel Booking",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Open E-Receipt (TODO)")),
                      );
                    },
                    child: const Text(
                      "E-Receipt",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ),
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
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: const Icon(Icons.arrow_back, color: KLPalette.text),
          ),
        ),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
        const Spacer(),
        const SizedBox(width: 48), // keep title centered
      ],
    );
  }
}

class _MainCard extends StatelessWidget {
  final BookingUi booking;
  final String timeText;

  const _MainCard({required this.booking, required this.timeText});

  @override
  Widget build(BuildContext context) {
    final statusChip = _StatusChip(status: booking.status);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 46, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header row (image + title/price/location + rating)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      height: 96,
                      width: 96,
                      color: KLPalette.mutedBg,
                      child: const Icon(Icons.image, color: KLPalette.text2, size: 46),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                booking.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                            const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 4),
                            Text(
                              booking.rating.toStringAsFixed(1),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "RM ${booking.unitPrice.toStringAsFixed(2)}",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 34),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.place, size: 18, color: KLPalette.text2),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                booking.locationText,
                                style: const TextStyle(
                                  color: KLPalette.text2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(height: 1, color: KLPalette.border),
              const SizedBox(height: 14),

              // Status row
              _KeyValueRow(
                label: "Status",
                valueWidget: statusChip,
              ),
              const SizedBox(height: 14),

              // Time row
              _KeyValueRow(
                label: "Time",
                valueText: timeText,
                valueStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 14),

              const Divider(height: 1, color: KLPalette.border),
              const SizedBox(height: 14),

              // Total row
              _KeyValueRow(
                label: "Total Amount",
                valueText: "RM ${booking.totalAmount.toStringAsFixed(2)}",
                valueStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
              ),

              const SizedBox(height: 14),

              // Map placeholder
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: double.infinity,
                    color: KLPalette.mutedBg,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: Opacity(
                            opacity: 0.65,
                            child: Icon(Icons.map_outlined, size: 170, color: KLPalette.text2),
                          ),
                        ),
                        // marker (center-ish)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              height: 56,
                              width: 56,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: KLPalette.border),
                              ),
                              child: Center(
                                child: Container(
                                  height: 44,
                                  width: 44,
                                  decoration: BoxDecoration(
                                    color: KLPalette.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.person, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String? valueText;
  final TextStyle? valueStyle;
  final Widget? valueWidget;

  const _KeyValueRow({
    required this.label,
    this.valueText,
    this.valueStyle,
    this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      color: KLPalette.text2,
      fontWeight: FontWeight.w800,
      fontSize: 18,
    );

    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        if (valueWidget != null)
          valueWidget!
        else
          Text(valueText ?? "", style: valueStyle ?? const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final BookingStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isUpcoming = status == BookingStatus.upcoming;

    final bg = isUpcoming ? const Color(0xFFFFF3D6) : const Color(0xFFD1FAE5);
    final fg = isUpcoming ? const Color(0xFFB45309) : const Color(0xFF047857);
    final text = isUpcoming ? "Upcoming" : "Completed";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w900, color: fg),
      ),
    );
  }
}

String _formatBookingTime(DateTime dt) {
  // Example: April 17, 2024, 9:00 AM
  final month = _monthName(dt.month);
  final day = dt.day;
  final year = dt.year;

  int hour = dt.hour;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = hour >= 12 ? "PM" : "AM";
  hour = hour % 12;
  if (hour == 0) hour = 12;

  return "$month $day, $year, $hour:$minute $ampm";
}

String _monthName(int m) {
  const names = [
    "January","February","March","April","May","June",
    "July","August","September","October","November","December"
  ];
  return names[(m - 1).clamp(0, 11)];
}