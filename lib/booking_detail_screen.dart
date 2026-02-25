import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fyp_flutter/utils/app_snack.dart';
import 'package:fyp_flutter/utils/provider_public_card.dart';
import 'package:fyp_flutter/utils/service_thumb.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'detail_payment_screen.dart';
import 'theme.dart';
import 'seeker_nav_controller.dart';
import 'leave_review_screen.dart';
import 'seeker_booking_firestore.dart';

class BookingDetailScreen extends StatelessWidget {
  final String bookingId;
  final SeekerNavController nav;

  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    required this.nav,
  });

  Map<String, dynamic> _paymentMap(Map<String, dynamic> d) {
    final p = d["payment"];
    if (p is Map) return Map<String, dynamic>.from(p as Map);
    return <String, dynamic>{};
  }

  bool _isCard(String method) {
    final m = method.toLowerCase();
    return m == "card" || m.contains("card");
  }

  bool _needsSeekerConfirm(String state) {
    final s = state.toLowerCase();
    if (s.isEmpty) return true; // treat unknown as pending
    if (s.contains("captur")) return false;
    if (s.contains("paid")) return false;
    if (s.contains("received")) return false;
    return s.contains("await") || s.contains("author") || s.contains("hold") || s.contains("pending");
  }

  String _paymentMethodLabel(String method) {
    final m = method.toLowerCase();
    if (_isCard(m)) return "Card";
    if (m.contains("cash")) return "Cash";
    return method.isEmpty ? "Payment" : method;
  }

  String _paymentStateLabel({required String method, required String state, required BookingStatus bookingStatus}) {
    final m = method.toLowerCase();
    final s = state.toLowerCase();
    if (m.contains("cash")) {
      if (s.contains("received") || s.contains("paid")) return "Received";
      if (bookingStatus == BookingStatus.completed) return "Awaiting cash";
      return "Pay on service";
    }
    // Card
    if (s.contains("captur")) return "Captured";
    if (s.contains("await")) return "Awaiting your confirmation";
    if (s.contains("author") || s.contains("hold")) return "Deposit authorized";
    if (s.contains("fail")) return "Failed";
    if (s.isEmpty) return "Pending";
    return state;
  }

  Future<void> _confirmServiceCompleted(BuildContext context, String bookingId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm service completed?"),
        content: const Text(
          "This will release the card payment to the provider.\n\nOnly confirm if the service has been completed.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Not yet")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirm")),
        ],
      ),
    );

    if (ok != true) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable("confirmServiceCompleted");
      await callable.call({"bookingId": bookingId});
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      AppSnack.show(context, "Confirmed. Payment released.", type: AppSnackType.success);
    } on FirebaseFunctionsException catch (e) {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      AppSnack.show(context, e.message ?? "Failed to confirm.", type: AppSnackType.error);
    } catch (_) {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      AppSnack.show(context, "Failed to confirm.", type: AppSnackType.error);
    }
  }

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('bookings').doc(bookingId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: KLPalette.bg,
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        final doc = snap.data!;
        if (!doc.exists) {
          return Scaffold(
            backgroundColor: KLPalette.bg,
            body: SafeArea(
              child: Column(
                children: [
                  _TopBar(title: "Detail Booking", onBack: () => Navigator.pop(context)),
                  const SizedBox(height: 18),
                  const Expanded(
                    child: Center(child: Text("Booking not found")),
                  ),
                ],
              ),
            ),
          );
        }

        final booking = BookingUi.fromDoc(doc);
        final raw = doc.data() ?? <String, dynamic>{};
        final pay = _paymentMap(raw);
        final payMethod = (pay["method"] ?? raw["paymentMethod"] ?? booking.paymentMethod).toString();
        final payState = (pay["state"] ?? "").toString();
        final payMethodLabel = _paymentMethodLabel(payMethod);
        final payStateLabel = _paymentStateLabel(
          method: payMethod,
          state: payState,
          bookingStatus: booking.status,
        );
        final needsSeekerConfirm =
            booking.status == BookingStatus.completed && _isCard(payMethod) && _needsSeekerConfirm(payState);

        final timeText = _formatBookingTime(booking.scheduledAt);
        final isUpcoming = booking.status == BookingStatus.upcoming;
        final isReviewed = booking.isReviewed;

        return Scaffold(
          backgroundColor: KLPalette.bg,
          body: SafeArea(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [KLPalette.tint50, KLPalette.bg],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Column(
                  children: [
                    _TopBar(
                      title: "Booking Detail",
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
                            nav: nav,
                            paymentMethodLabel: payMethodLabel,
                            paymentStateLabel: payStateLabel,
                          ),
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
                                      color: isUpcoming
                                          ? const Color(0xFFFBBF24)
                                          : KLPalette.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isUpcoming
                                          ? Icons.access_time_rounded
                                          : Icons.check_rounded,
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

          // Bottom actions
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
                          backgroundColor: isUpcoming
                              ? const Color(0xFFFFE4E6)
                              : (needsSeekerConfirm ? KLPalette.primary : KLPalette.tint100),
                          foregroundColor: isUpcoming
                              ? const Color(0xFFEF4444)
                              : (needsSeekerConfirm ? Colors.white : KLPalette.primary700),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        onPressed: () async {
                          if (isUpcoming) {
                            final reason = await _showCancelSheet(context);
                            if (reason == null) return;

                            final batch = FirebaseFirestore.instance.batch();

                            batch.update(_ref, {
                              "status": "cancelled",
                              "cancelReason": reason,
                              "updatedAt": FieldValue.serverTimestamp(),
                            });

                            batch.set(_ref.collection("history").doc(), {
                              "at": FieldValue.serverTimestamp(),
                              "title": "Cancelled",
                              "subtitle": "Cancelled by seeker",
                              "actorUid": FirebaseAuth.instance.currentUser?.uid ?? "unknown",
                            });

                            await batch.commit();

                            if (!context.mounted) return;
                            await _showCancelSuccessDialog(context, booking);

                            if (!context.mounted) return;
                            Navigator.pop(context);
                          } else if (needsSeekerConfirm) {
                            await _confirmServiceCompleted(context, booking.id);
                          } else {
                            if (isReviewed) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("You already reviewed this booking.")),
                              );
                              return;
                            }

                            final submitted = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LeaveReviewScreen(booking: booking, nav: nav),
                              ),
                            );

                            if (submitted == true) {
                              await _ref.update({
                                "isReviewed": true,
                                "updatedAt": FieldValue.serverTimestamp(),
                              });
                            }
                          }
                        },
                        child: Text(
                          isUpcoming
                              ? "Cancel Booking"
                              : (needsSeekerConfirm
                              ? "Confirm Completed"
                              : (isReviewed ? "Reviewed" : "Leave a Review")),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: () async {
                          final heroUrl = await fetchServiceHeroUrl(booking.serviceId);
                          if (!context.mounted) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetailPaymentScreen(
                                nav: nav,
                                serviceTitle: booking.title,
                                rating: booking.serviceRating,
                                locationText: booking.locationText,
                                paymentMethod: payMethodLabel,
                                paymentStatus: payStateLabel,
                                paymentData: pay,
                                date: booking.scheduledAt,
                                startTime: _formatStartTime(booking.scheduledAt),
                                transactionId: bookingId,
                                totalAmount: booking.totalAmount,
                                serviceImageUrl: heroUrl,
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          "E-Receipt",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatStartTime(DateTime dt) {
    int hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return "$hour:$minute $ampm";
  }

  Future<String?> _showCancelSheet(BuildContext context) {
    String? reason;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: KLPalette.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                final canConfirm = reason != null;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        const Text(
                          "Cancel Booking",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context, null),
                          icon: const Icon(Icons.close, color: KLPalette.text),
                        ),
                      ],
                    ),
                    const Divider(height: 1, color: KLPalette.border),

                    const SizedBox(height: 18),
                    const Text(
                      "Are you sure want to cancel\nyour service booking?",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        height: 1.15,
                        color: KLPalette.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Only 80% of the money you can refund from\nyour payment according to our policy",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
                    ),

                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Reason",
                        style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text),
                      ),
                    ),
                    const SizedBox(height: 10),

                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () async {
                        final picked = await _pickCancelReason(context);
                        if (picked == null) return;
                        setSheetState(() => reason = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: KLPalette.border),
                          color: KLPalette.mutedBg,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                reason ?? "Choose the reason",
                                style: TextStyle(
                                  color: reason == null ? KLPalette.text2 : KLPalette.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: KLPalette.text),
                          ],
                        ),
                      ),
                    ),

                    if (!canConfirm) ...[
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Please select a reason to continue",
                          style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Divider(height: 1, color: KLPalette.border),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: KLPalette.tint100,
                                foregroundColor: KLPalette.text,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              ),
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text("Back", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: KLPalette.tint200,
                                disabledForegroundColor: KLPalette.text2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              ),
                              onPressed: canConfirm ? () => Navigator.pop(context, reason) : null,
                              child: const Text("Cancel Booking", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<String?> _pickCancelReason(BuildContext context) async {
    const reasons = [
      "Change of schedule",
      "Found another service",
      "Too expensive",
      "Booked by mistake",
      "Other",
    ];

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: reasons.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            return ListTile(
              title: Text(reasons[i], style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(context, reasons[i]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showCancelSuccessDialog(BuildContext context, BookingUi booking) {
    final refund = (booking.totalAmount * 0.8);

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Container(
              color: KLPalette.bg,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _ConfettiCheck(),
                  const SizedBox(height: 14),
                  const Text(
                    "Cancel Booking\nSuccessful",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 34,
                      height: 1.05,
                      color: KLPalette.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "You have successfully canceled your service\nbooking. 80% funds will be returned to your\naccount. RM ${refund.toStringAsFixed(0)}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: KLPalette.text2,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: KLPalette.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "Okay",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConfettiCheck extends StatelessWidget {
  const _ConfettiCheck();

  @override
  Widget build(BuildContext context) {
    final dots = [KLPalette.tint50, KLPalette.tint100, KLPalette.tint200];

    return SizedBox(
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...[
            const Offset(-90, -20),
            const Offset(-60, 20),
            const Offset(-10, -30),
            const Offset(70, -10),
            const Offset(90, 25),
            const Offset(30, 35),
          ].asMap().entries.map((e) {
            final i = e.key;
            final o = e.value;
            return Positioned(
              left: 70 + o.dx,
              top: 70 + o.dy,
              child: Container(
                height: 14,
                width: 14,
                decoration: BoxDecoration(
                  color: dots[i % dots.length],
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),

          Container(
            height: 92,
            width: 92,
            decoration: const BoxDecoration(
              color: KLPalette.primary,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 48),
            ),
          ),
        ],
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
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        const Spacer(),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _MainCard extends StatelessWidget {
  final BookingUi booking;
  final String timeText;
  final SeekerNavController nav;

  final String paymentMethodLabel;
  final String paymentStateLabel;

  const _MainCard({
    required this.booking,
    required this.timeText,
    required this.nav,
    required this.paymentMethodLabel,
    required this.paymentStateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final statusChip = _StatusChip(status: booking.status);

    final canShowReview = booking.isReviewed && booking.reviewStars != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 46, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              height: 96,
                              width: 96,
                              color: KLPalette.mutedBg,
                              child: ServiceThumb(
                                model: booking,
                                placeholderBg: KLPalette.mutedBg,
                                placeholderIconColor: KLPalette.text2,
                                iconSize: 46,
                                fit: BoxFit.cover,
                              ),
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
                                            fontSize: 22),
                                      ),
                                    ),
                                    const Icon(Icons.star_rounded,
                                        color: Color(0xFFFBBF24)),
                                    const SizedBox(width: 4),
                                    Text(
                                      booking.serviceRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "RM ${booking.totalAmount.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 34),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.place, size: 18,
                                        color: KLPalette.text2),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        booking.locationText,
                                        style: const TextStyle(
                                            color: KLPalette.text2,
                                            fontWeight: FontWeight.w800),
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

                      _KeyValueRow(label: "Status", valueWidget: statusChip),
                      const SizedBox(height: 12),
                      _KeyValueRow(
                        label: "Payment",
                        valueText: "$paymentMethodLabel • $paymentStateLabel",
                        valueStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 14),
                      _KeyValueRow(
                        label: "Time",
                        valueText: timeText,
                        valueStyle: const TextStyle(fontWeight: FontWeight.w900,
                            fontSize: 18),
                      ),

                      const SizedBox(height: 14),
                      const Divider(height: 1, color: KLPalette.border),
                      const SizedBox(height: 14),

                      _KeyValueRow(
                        label: "Total Amount",
                        valueText: "RM ${booking.totalAmount.toStringAsFixed(
                            2)}",
                        valueStyle: const TextStyle(fontWeight: FontWeight.w900,
                            fontSize: 28),
                      ),

                      const SizedBox(height: 14),

                      ProviderPublicCard(
                        providerId: booking.providerId,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProviderProfileScreen(
                                providerId: booking.providerId,
                                nav: nav,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      if (canShowReview) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: KLPalette.border),
                        const SizedBox(height: 14),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: KLPalette.tint50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: KLPalette.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    "Your Review",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                          color: KLPalette.border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, size: 18,
                                            color: Color(0xFFFBBF24)),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${booking.reviewStars}.0",
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 10),

                              Row(
                                children: [
                                  const Icon(Icons.event, size: 18,
                                      color: KLPalette.text2),
                                  const SizedBox(width: 6),
                                  Text(
                                    _ddmmyyyy(booking.reviewedAt),
                                    style: const TextStyle(
                                      color: KLPalette.text2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  const _VerifiedPill(text: "Verified"),
                                ],
                              ),

                              if ((booking.reviewText ?? "")
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  booking.reviewText!.trim(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    height: 1.35,
                                  ),
                                ),
                              ] else
                                ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    "No written comment.",
                                    style: TextStyle(
                                      color: KLPalette.text2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: _BookingMapCard(
                            bookingLat: booking.locationLat,
                            bookingLng: booking.locationLng,
                            providerLat: booking.providerLat,
                            providerLng: booking.providerLng,
                            label: booking.locationText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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

    final bg = switch (status) {
      BookingStatus.upcoming => const Color(0xFFFFF3D6),
      BookingStatus.completed => const Color(0xFFD1FAE5),
      BookingStatus.cancelled => const Color(0xFFFEE2E2),
    };

    final fg = switch (status) {
      BookingStatus.upcoming => const Color(0xFFB45309),
      BookingStatus.completed => const Color(0xFF047857),
      BookingStatus.cancelled => const Color(0xFFB91C1C),
    };

    final text = switch (status) {
      BookingStatus.upcoming => "Upcoming",
      BookingStatus.completed => "Completed",
      BookingStatus.cancelled => "Cancelled",
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w900, color: fg)),
    );
  }
}

String _formatBookingTime(DateTime dt) {
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

String _ddmmyyyy(DateTime? dt) {
  if (dt == null) return "—";
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  return "$dd/$mm/${dt.year}";
}

class _BookingMap extends StatelessWidget {
  final double? lat;
  final double? lng;

  const _BookingMap({required this.lat, required this.lng});

  @override
  Widget build(BuildContext context) {
    if (lat == null || lng == null) {
      return Container(
        width: double.infinity,
        color: KLPalette.mutedBg,
        child: const Center(
          child: Text(
            "No location pin available",
            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    final pos = LatLng(lat!, lng!);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: pos, zoom: 15),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      liteModeEnabled: true,
      markers: {
        Marker(
          markerId: const MarkerId("booking_location"),
          position: pos,
        ),
      },
    );
  }
}

class _VerifiedPill extends StatelessWidget {
  final String text;
  const _VerifiedPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KLPalette.tint50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 16, color: KLPalette.primary),
          SizedBox(width: 6),
          Text(
            text,
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

class _BookingMapCard extends StatelessWidget {
  final double? bookingLat;
  final double? bookingLng;
  final double? providerLat;
  final double? providerLng;
  final String label;

  const _BookingMapCard({
    required this.bookingLat,
    required this.bookingLng,
    required this.providerLat,
    required this.providerLng,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (bookingLat == null || bookingLng == null) {
      return Container(
        color: KLPalette.mutedBg,
        child: const Center(
          child: Text(
            "No location pin available",
            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    final bookingPos = LatLng(bookingLat!, bookingLng!);

    final hasProvider = providerLat != null && providerLng != null;
    final providerPos = hasProvider ? LatLng(providerLat!, providerLng!) : null;

    final distanceKm = hasProvider
        ? _haversineKm(bookingLat!, bookingLng!, providerLat!, providerLng!)
        : null;

    return Stack(
      children: [
        Positioned.fill(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullMapScreen(
                    bookingPos: bookingPos,
                    providerPos: providerPos,
                    label: label,
                  ),
                ),
              );
            },
            child: AbsorbPointer(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: bookingPos, zoom: 15),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                liteModeEnabled: true,
                markers: {
                  Marker(
                    markerId: const MarkerId("booking_location"),
                    position: bookingPos,
                  ),
                  if (providerPos != null)
                    Marker(
                      markerId: const MarkerId("provider_location"),
                      position: providerPos,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                    ),
                },
              ),
            ),
          ),
        ),

        // address pill
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KLPalette.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.place, size: 18, color: KLPalette.text2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Legend (pin colors)
        Positioned(
          left: 12,
          top: 64,
          child: _MapLegend(
            items: [
              const _LegendItem(Color(0xFFEF4444), "Your address"),
              if (providerPos != null) const _LegendItem(Color(0xFF3B82F6), "Provider"),
            ],
          ),
        ),

        // distance pill
        if (distanceKm != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: KLPalette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.social_distance, size: 18, color: KLPalette.text2),
                  const SizedBox(width: 8),
                  Text(
                    "${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km away",
                    style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text),
                  ),
                ],
              ),
            ),
          ),

        // Navigate button - booking location
        Positioned(
          right: 12,
          bottom: 12,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _openGoogleMaps(bookingLat!, bookingLng!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: KLPalette.primary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: KLPalette.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    "Navigate",
                    style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openGoogleMaps(double lat, double lng) async {
    final url = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving",
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      final pin = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
      await launchUrl(pin, mode: LaunchMode.externalApplication);
    }
  }
}

class _LegendItem {
  final Color color;
  final String label;
  const _LegendItem(this.color, this.label);
}

class _MapLegend extends StatelessWidget {
  final List<_LegendItem> items;
  const _MapLegend({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KLPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Legend", style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final it in items) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 10,
                    width: 10,
                    decoration: BoxDecoration(color: it.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    it.label,
                    style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              if (it != items.last) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _MapActionButton({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: KLPalette.primary,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: KLPalette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double d2r(double d) => d * (math.pi / 180.0);
  final dLat = d2r(lat2 - lat1);
  final dLon = d2r(lon2 - lon1);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(d2r(lat1)) * math.cos(d2r(lat2)) *
          math.sin(dLon / 2) * math.sin(dLon / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

class FullMapScreen extends StatefulWidget {
  final LatLng bookingPos;
  final LatLng? providerPos;
  final String label;

  const FullMapScreen({
    super.key,
    required this.bookingPos,
    required this.providerPos,
    required this.label,
  });

  @override
  State<FullMapScreen> createState() => _FullMapScreenState();
}

class _FullMapScreenState extends State<FullMapScreen> {
  GoogleMapController? _controller;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId("booking_location"),
        position: widget.bookingPos,
        infoWindow: InfoWindow(title: "Booking Location", snippet: widget.label),
      ),
      if (widget.providerPos != null)
        Marker(
          markerId: const MarkerId("provider_location"),
          position: widget.providerPos!,
          infoWindow: const InfoWindow(title: "Provider Location"),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: widget.bookingPos, zoom: 15),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              liteModeEnabled: false,
              markers: markers,
              onMapCreated: (c) {
                _controller = c;
                _fitBounds();
              },
            ),

            // Legend (pin colors)
            Positioned(
              left: 12,
              bottom: 84, // sits above bottom buttons
              child: _MapLegend(
                items: [
                  const _LegendItem(Color(0xFFEF4444), "Your address"),
                  if (widget.providerPos != null) const _LegendItem(Color(0xFF3B82F6), "Provider"),
                ],
              ),
            ),

            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        shape: BoxShape.circle,
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: const Icon(Icons.arrow_back, color: KLPalette.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.map_outlined, size: 18, color: KLPalette.text2),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Map",
                              style: const TextStyle(fontWeight: FontWeight.w900),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            widget.providerPos != null ? "2 pins" : "1 pin",
                            style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: KLPalette.tint100,
                          foregroundColor: KLPalette.text,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: _fitBounds,
                        child: const Text("Recenter", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: KLPalette.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: () => _openGoogleMaps(widget.bookingPos.latitude, widget.bookingPos.longitude),
                        child: const Text("Navigate", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
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

  void _fitBounds() {
    if (_controller == null) return;

    final points = <LatLng>[widget.bookingPos];
    if (widget.providerPos != null) points.add(widget.providerPos!);

    if (points.length == 1) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  Future<void> _openGoogleMaps(double lat, double lng) async {
    final url = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving",
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      final pin = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
      await launchUrl(pin, mode: LaunchMode.externalApplication);
    }
  }
}

class ProviderProfileScreen extends StatelessWidget {
  final String providerId;
  final SeekerNavController nav;

  const ProviderProfileScreen({
    super.key,
    required this.providerId,
    required this.nav,
  });

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('users').doc(providerId);

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [KLPalette.tint50, KLPalette.bg],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: ref.snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Column(
                    children: [
                      _TopBar(title: "Provider", onBack: () => Navigator.pop(context)),
                      const SizedBox(height: 18),
                      const Expanded(child: Center(child: CircularProgressIndicator())),
                    ],
                  );
                }

                final doc = snap.data!;
                if (!doc.exists) {
                  return Column(
                    children: [
                      _TopBar(title: "Provider", onBack: () => Navigator.pop(context)),
                      const SizedBox(height: 18),
                      const Expanded(child: Center(child: Text("Provider not found"))),
                    ],
                  );
                }

                final m = doc.data() ?? const <String, dynamic>{};

                String pickStr(dynamic v) => (v is String) ? v.trim() : "";
                String pickStrAny(List<dynamic> vs) {
                  for (final v in vs) {
                    final s = pickStr(v);
                    if (s.isNotEmpty) return s;
                  }
                  return "";
                }

                final name = pickStrAny([m['name'], m['displayName'], m['providerName']]);
                final email = pickStrAny([m['email'], m['providerEmail']]);
                final phone = pickStrAny([m['phone'], m['phoneNumber'], m['contactNumber']]);
                final photoUrl = pickStrAny([m['photoUrl'], m['profilePhotoUrl'], m['avatarUrl']]);
                final bio = pickStrAny([m['bio'], m['about'], m['description']]);

                // Business address supports:
                // A) string: "No 3, Jalan ..."
                // B) map: { text: "...", lat: 3.1, lng: 101.6 }
                String businessText = "";
                double? bizLat;
                double? bizLng;

                final biz = m['businessAddress'];
                if (biz is String) {
                  businessText = biz.trim();
                } else if (biz is Map) {
                  final mm = biz.cast<String, dynamic>();
                  businessText = pickStrAny([mm['text'], mm['address'], mm['label']]);
                  final lt = mm['lat'];
                  final lg = mm['lng'];
                  if (lt is num) bizLat = lt.toDouble();
                  if (lg is num) bizLng = lg.toDouble();
                }

                final areas = (m['serviceAreas'] is List)
                    ? (m['serviceAreas'] as List).map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
                    : <String>[];

                final workingHoursRaw = (m['workingHours'] is Map)
                    ? (m['workingHours'] as Map).cast<String, dynamic>()
                    : <String, dynamic>{};

                return Column(
                  children: [
                    _TopBar(title: "Provider", onBack: () => Navigator.pop(context)),
                    const SizedBox(height: 14),

                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 110),
                        children: [
                          _ProviderHeaderCard(
                            name: name.isEmpty ? "Provider" : name,
                            email: email,
                            photoUrl: photoUrl,
                            onChat: () {
                              nav.goChatWith(providerId);
                              Navigator.popUntil(context, (route) => route.isFirst);
                            },
                            onCall: phone.isEmpty ? null : () => _openTel(context, phone),
                            onEmail: email.isEmpty ? null : () => _openEmail(context, email),
                            onMaps: (businessText.isEmpty && bizLat == null)
                                ? null
                                : () {
                              if (bizLat != null && bizLng != null) {
                                _openGoogleMapsLatLng(context, bizLat!, bizLng!);
                              } else {
                                _openGoogleMapsQuery(context, businessText);
                              }
                            },
                          ),

                          if (bio.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _InfoCard(
                              title: "About",
                              child: Text(
                                bio,
                                style: const TextStyle(
                                  color: KLPalette.text2,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),
                          _InfoCard(
                            title: "Business address",
                            trailing: (businessText.isNotEmpty || (bizLat != null && bizLng != null))
                                ? TextButton.icon(
                              onPressed: () {
                                if (bizLat != null && bizLng != null) {
                                  _openGoogleMapsLatLng(context, bizLat!, bizLng!);
                                } else {
                                  _openGoogleMapsQuery(context, businessText);
                                }
                              },
                              icon: const Icon(Icons.map_outlined, size: 18),
                              label: const Text("Open"),
                            )
                                : null,
                            child: Text(
                              businessText.isEmpty ? "—" : businessText,
                              style: const TextStyle(
                                color: KLPalette.text2,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                          _InfoCard(
                            title: "Service areas",
                            child: areas.isEmpty
                                ? const Text(
                              "—",
                              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                            )
                                : Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: areas.map((a) => _Pill(text: a)).toList(),
                            ),
                          ),

                          const SizedBox(height: 12),
                          _WorkingHoursCard(workingHoursRaw: workingHoursRaw),

                          const SizedBox(height: 12),
                          _ProviderServicesPreview(providerId: providerId),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),

      // Sticky bottom: Chat (primary action)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: KLPalette.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: () {
                nav.goChatWith(providerId);
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text("Chat with provider", style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _openTel(BuildContext context, String phone) async {
    final p = phone.replaceAll(RegExp(r"\s+"), "");
    final url = Uri.parse("tel:$p");
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Unable to open dialer.")));
    }
  }

  static Future<void> _openEmail(BuildContext context, String email) async {
    final url = Uri(
      scheme: "mailto",
      path: email,
      queryParameters: {"subject": "KLServeLink Support"},
    );
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Unable to open email app.")));
    }
  }

  static Future<void> _openGoogleMapsQuery(BuildContext context, String query) async {
    final q = Uri.encodeComponent(query.trim());
    final url = Uri.parse("https://www.google.com/maps/search/?api=1&query=$q");
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Unable to open Google Maps.")));
    }
  }

  static Future<void> _openGoogleMapsLatLng(BuildContext context, double lat, double lng) async {
    final url = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Unable to open Google Maps.")));
    }
  }
}

class _ProviderHeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String photoUrl;
  final VoidCallback onChat;
  final VoidCallback? onCall;
  final VoidCallback? onEmail;
  final VoidCallback? onMaps;

  const _ProviderHeaderCard({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.onChat,
    required this.onCall,
    required this.onEmail,
    required this.onMaps,
  });

  @override
  Widget build(BuildContext context) {
    Widget avatar() {
      if (photoUrl.trim().isEmpty) {
        return const CircleAvatar(
          radius: 36,
          backgroundColor: KLPalette.mutedBg,
          child: Icon(Icons.person, color: KLPalette.text2, size: 34),
        );
      }

      return CircleAvatar(
        radius: 36,
        backgroundColor: KLPalette.mutedBg,
        child: ClipOval(
          child: Image.network(
            photoUrl,
            fit: BoxFit.cover,
            width: 72,
            height: 72,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            },
            errorBuilder: (context, error, stackTrace) {
              debugPrint("IMAGE ERROR: $error");
              return const Icon(Icons.person, size: 34);
            },
          ),
        ),
      );
    }

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
          children: [
            Row(
              children: [
                avatar(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      const SizedBox(height: 6),
                      Text(
                        email.isEmpty ? "—" : email,
                        style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      const _VerifiedPill(text: "Provider"),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: KLPalette.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: onChat,
                      child: const Text("Chat", style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _MiniAction(icon: Icons.call_outlined, onTap: onCall),
                const SizedBox(width: 10),
                _MiniAction(icon: Icons.mail_outline_rounded, onTap: onEmail),
                const SizedBox(width: 10),
                _MiniAction(icon: Icons.map_outlined, onTap: onMaps),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _MiniAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Opacity(
        opacity: disabled ? 0.35 : 1,
        child: Container(
          height: 50,
          width: 50,
          decoration: BoxDecoration(
            color: KLPalette.tint50,
            shape: BoxShape.circle,
            border: Border.all(color: KLPalette.border),
          ),
          child: Icon(icon, color: KLPalette.primary700),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _InfoCard({required this.title, required this.child, this.trailing});

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
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KLPalette.tint50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KLPalette.border),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700)),
    );
  }
}

class _WorkingHoursCard extends StatelessWidget {
  final Map<String, dynamic> workingHoursRaw;
  const _WorkingHoursCard({required this.workingHoursRaw});

  @override
  Widget build(BuildContext context) {
    final rows = _formatWorkingHours(workingHoursRaw);

    return _InfoCard(
      title: "Working hours",
      child: rows.isEmpty
          ? const Text(
        "—",
        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
      )
          : Column(
        children: rows.map((r) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    r.day,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const Spacer(),
                Text(
                  r.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: r.isClosed ? const Color(0xFFB91C1C) : KLPalette.text,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  static List<_WhRow> _formatWorkingHours(Map<String, dynamic> raw) {
    if (raw.isEmpty) return [];

    // Format A:
    // { "days": [ { "weekday": 1, "startHour": 9, "endHour": 17, "enabled": true }, ... ] }
    final days = raw['days'];
    if (days is List) {
      final map = <int, _WhRow>{};
      for (final x in days) {
        if (x is! Map) continue;
        final m = x.cast<String, dynamic>();
        final wd = (m['weekday'] as num?)?.toInt(); // 1..7
        if (wd == null) continue;

        final enabled = (m['enabled'] ?? true) == true;
        if (!enabled) {
          map[wd] = _WhRow(_wdShort(wd), "Closed", true);
          continue;
        }
        final sh = (m['startHour'] as num?)?.toInt();
        final eh = (m['endHour'] as num?)?.toInt();
        if (sh == null || eh == null) continue;

        map[wd] = _WhRow(_wdShort(wd), "${_hh(sh)}–${_hh(eh)}", false);
      }

      return List.generate(7, (i) {
        final wd = i + 1;
        return map[wd] ?? _WhRow(_wdShort(wd), "—", false);
      });
    }

    // Format B:
    // { "mon": { "start": "09:00", "end": "18:00", "enabled": true }, ... }
    final order = const ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
    final out = <_WhRow>[];
    for (final k in order) {
      final v = raw[k];
      if (v is! Map) {
        out.add(_WhRow(k[0].toUpperCase() + k.substring(1), "—", false));
        continue;
      }
      final m = v.cast<String, dynamic>();
      final enabled = (m['enabled'] ?? false) == true;
      if (!enabled) {
        out.add(_WhRow(k[0].toUpperCase() + k.substring(1), "Closed", true));
        continue;
      }
      final start = (m['start'] ?? '').toString();
      final end = (m['end'] ?? '').toString();
      final label = (start.isEmpty || end.isEmpty) ? "—" : "$start–$end";
      out.add(_WhRow(k[0].toUpperCase() + k.substring(1), label, false));
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

  static String _hh(int h) => "${h.toString().padLeft(2, '0')}:00";
}

class _WhRow {
  final String day;
  final String label;
  final bool isClosed;
  const _WhRow(this.day, this.label, this.isClosed);
}

class _ProviderServicesPreview extends StatelessWidget {
  final String providerId;
  const _ProviderServicesPreview({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('services')
        .where('providerId', isEqualTo: providerId)
        .where('status', isEqualTo: 'active');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _InfoCard(
            title: "Active services",
            child: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return _InfoCard(
            title: "Active services",
            child: const Text(
              "No active services listed.",
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
            ),
          );
        }

        final show = docs.take(4).toList();

        return _InfoCard(
          title: "Active services",
          child: Column(
            children: show.map((d) {
              final m = d.data();
              final name = (m['name'] ?? 'Service').toString();
              final cat = (m['category'] ?? '').toString();
              final price = (m['price'] is num) ? (m['price'] as num).toDouble() : null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: KLPalette.mutedBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: const Icon(Icons.storefront_rounded, color: KLPalette.text2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(
                            cat.isEmpty ? "—" : cat,
                            style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    if (price != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: KLPalette.tint50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: KLPalette.border),
                        ),
                        child: Text(
                          "RM ${price.toStringAsFixed(0)}",
                          style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

Future<String?> fetchServiceHeroUrl(String serviceId) async {
  try {
    final doc = await FirebaseFirestore.instance.collection('services').doc(serviceId).get();
    final m = doc.data() ?? {};

    final thumb = (m['thumbnailUrl'] ?? '').toString().trim();
    final photos = (m['photoUrls'] as List?)?.cast<dynamic>() ?? const [];
    final first = photos.isNotEmpty ? photos.first.toString().trim() : '';

    if (thumb.isNotEmpty) return thumb;
    if (first.isNotEmpty) return first;
    return null;
  } catch (_) {
    return null;
  }
}