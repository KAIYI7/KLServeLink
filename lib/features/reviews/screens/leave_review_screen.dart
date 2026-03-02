import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import '../../seeker/navigation/seeker_nav_controller.dart';
import '../../seeker/bookings/data/seeker_booking_firestore.dart';
import 'package:fyp_flutter/core/widgets/service_thumb.dart';

class LeaveReviewScreen extends StatefulWidget {
  final BookingUi booking;
  final SeekerNavController nav;

  const LeaveReviewScreen({
    super.key,
    required this.booking,
    required this.nav,
  });

  @override
  State<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends State<LeaveReviewScreen> {
  int stars = 0;
  final ctrl = TextEditingController();

  bool isSubmitting = false;

  DocumentReference<Map<String, dynamic>> get _bookingRef =>
      FirebaseFirestore.instance.collection('bookings').doc(widget.booking.id);

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_onReviewChanged);
  }

  void _onReviewChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    ctrl.removeListener(_onReviewChanged);
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _bookingRef.snapshots(),
      builder: (context, snap) {
        final b = (snap.hasData && snap.data!.exists)
            ? BookingUi.fromDoc(snap.data!)
            : widget.booking;

        final canSubmit = stars > 0 && ctrl.text.trim().isNotEmpty && !isSubmitting;

        return Scaffold(
          backgroundColor: KLPalette.bg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                children: [
                  _TopBar(
                    title: "Leave a Review",
                    onBack: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 16),

                  _ServiceHeaderCard(b: b),
                  const SizedBox(height: 18),

                  const Divider(height: 1, color: KLPalette.border),
                  const SizedBox(height: 18),

                  const Text(
                    "How is the service ?",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34, height: 1.05),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Please give your rating & also your review",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),

                  _StarsRow(
                    value: stars,
                    onChanged: (v) => setState(() => stars = v),
                  ),

                  const SizedBox(height: 14),

                  Expanded(
                    child: _ReviewBox(
                      controller: ctrl,
                      maxLen: 200,
                    ),
                  ),
                ],
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
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          side: const BorderSide(color: KLPalette.border),
                        ),
                        onPressed: isSubmitting ? null : () => Navigator.pop(context),
                        child: const Text(
                          "Cancel",
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
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: !canSubmit ? null : _submit,
                        child: const Text(
                          "Submit",
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
      },
    );
  }

  Future<void> _submit() async {
    setState(() => isSubmitting = true);

    try {
      final reviewText = ctrl.text.trim();
      final bookingId = widget.booking.id;

      final db = FirebaseFirestore.instance;
      final bookingRef = db.collection('bookings').doc(bookingId);
      final serviceRef = db.collection('services').doc(widget.booking.serviceId);

      await db.runTransaction((tx) async {
        final bookingSnap = await tx.get(bookingRef);
        if (!bookingSnap.exists) {
          throw StateError("Booking not found");
        }

        final b = bookingSnap.data() as Map<String, dynamic>;
        final status = (b['status'] ?? '').toString();
        final already = (b['isReviewed'] ?? false) == true;

        if (status != 'completed') {
          throw StateError("Only completed bookings can be reviewed");
        }
        if (already) {
          throw StateError("You already reviewed this booking");
        }

        final serviceSnap = await tx.get(serviceRef);
        if (!serviceSnap.exists) {
          throw StateError("Service not found");
        }

        final s = serviceSnap.data() as Map<String, dynamic>;

        final oldCount = (s['ratingCount'] is num) ? (s['ratingCount'] as num).toInt() : 0;
        final oldSum = (s['ratingSum'] is num) ? (s['ratingSum'] as num).toDouble() : 0.0;

        // starCounts stored as {"1":0.., "2":..., "5":...}
        final rawCounts = (s['starCounts'] is Map) ? Map<String, dynamic>.from(s['starCounts']) : <String, dynamic>{};
        for (final k in ['1','2','3','4','5']) {
          rawCounts.putIfAbsent(k, () => 0);
        }

        final newCount = oldCount + 1;
        final newSum = oldSum + stars.toDouble();
        final newAvg = newSum / newCount;

        rawCounts['$stars'] = ((rawCounts['$stars'] is num) ? (rawCounts['$stars'] as num).toInt() : 0) + 1;

        // create review under services/{serviceId}/reviews/{bookingId}
        final reviewRef = serviceRef.collection('reviews').doc(bookingId);
        tx.set(reviewRef, {
          "bookingId": bookingId,
          "serviceId": widget.booking.serviceId,
          "providerId": widget.booking.providerId,
          "seekerId": (b['seekerId'] ?? '').toString(),
          "seekerName": (b['seekerName'] ?? 'Seeker').toString(),
          "stars": stars,
          "text": reviewText,
          "verifiedJob": true,
          "createdAt": FieldValue.serverTimestamp(),
        });

        // update service aggregates
        tx.update(serviceRef, {
          "ratingCount": newCount,
          "ratingSum": newSum,
          "ratingAvg": newAvg,
          "starCounts": rawCounts,
          // "rating": newAvg,
          "updatedAt": FieldValue.serverTimestamp(),
        });

        // mark booking reviewed + store snapshot
        tx.update(bookingRef, {
          "isReviewed": true,
          "reviewStars": stars,
          "reviewText": reviewText,
          "reviewedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      await _showThankYouDialog(context);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to submit review: $e")),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _showThankYouDialog(BuildContext context) {
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
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _ConfettiCheck(),
                  const SizedBox(height: 14),
                  const Text(
                    "Thank You for Your\nFeedback",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34, height: 1.05),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Your rating helps us improve and ensures\ntop-notch service every time! 🙌",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF374151),
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
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Continue Booking Service",
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
              color: Colors.white,
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

class _ServiceHeaderCard extends StatelessWidget {
  final BookingUi b;
  const _ServiceHeaderCard({required this.b});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            height: 86,
            width: 110,
            color: KLPalette.mutedBg,
            child: ServiceThumb(
              model: b,
              placeholderBg: KLPalette.mutedBg,
              placeholderIconColor: KLPalette.text2,
              iconSize: 44,
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
                children: [
                  Expanded(
                    child: Text(
                      b.title,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 26),
                  const SizedBox(width: 6),
                  Text(
                    b.serviceRating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Text(
                "RM ${b.totalAmount.toStringAsFixed(2)}",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 34),
              ),

              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.place, size: 18, color: KLPalette.text2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      b.locationText,
                      style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StarsRow extends StatelessWidget {
  final int value; // 0-5
  final ValueChanged<int> onChanged;

  const _StarsRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final filled = (i + 1) <= value;
        return GestureDetector(
          onTap: () => onChanged(i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: 52,
              color: filled ? const Color(0xFFFBBF24) : const Color(0xFFCBD5E1),
            ),
          ),
        );
      }),
    );
  }
}

class _UploadBox extends StatelessWidget {
  final VoidCallback onTap;
  const _UploadBox({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Column(
          children: [
            OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text("Browse File", style: TextStyle(fontWeight: FontWeight.w900)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                side: const BorderSide(color: KLPalette.border),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "PNG, JPG (max 5MB)",
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewBox extends StatefulWidget {
  final TextEditingController controller;
  final int maxLen;

  const _ReviewBox({required this.controller, required this.maxLen});

  @override
  State<_ReviewBox> createState() => _ReviewBoxState();
}

class _ReviewBoxState extends State<_ReviewBox> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final len = widget.controller.text.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
              child: TextField(
                controller: widget.controller,
                maxLength: widget.maxLen,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: "Give a reviews...",
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: "",
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 12,
              child: Text(
                "$len/${widget.maxLen}",
                style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
              ),
            ),
            const Positioned(
              right: 14,
              bottom: 10,
              child: Icon(Icons.edit_outlined, color: KLPalette.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiCheck extends StatelessWidget {
  const _ConfettiCheck();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // confetti dots (theme tints)
          ...[
            const Offset(-90, -20),
            const Offset(-60, 20),
            const Offset(-10, -30),
            const Offset(70, -10),
            const Offset(90, 25),
            const Offset(30, 35),
          ].asMap().entries.map((entry) {
            final idx = entry.key;
            final o = entry.value;
            final colors = [KLPalette.tint50, KLPalette.tint100, KLPalette.tint200];

            return Positioned(
              left: 70 + o.dx,
              top: 70 + o.dy,
              child: Container(
                height: 14,
                width: 14,
                decoration: BoxDecoration(
                  color: colors[idx % colors.length],
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),

          // center badge (theme blue)
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