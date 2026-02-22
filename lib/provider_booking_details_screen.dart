import 'dart:async';
import 'dart:math' as math;
import 'package:fyp_flutter/utils/app_snack.dart';
import 'package:fyp_flutter/utils/service_thumb.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'booking_firestore.dart';
import 'provider_booking_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ProviderBookingDetailsScreen extends StatefulWidget {
  final String bookingId;
  const ProviderBookingDetailsScreen({super.key, required this.bookingId});

  @override
  State<ProviderBookingDetailsScreen> createState() => _ProviderBookingDetailsScreenState();
}

class _ProviderBookingDetailsScreenState extends State<ProviderBookingDetailsScreen> {
  final api = BookingFirestore();
  Future<double?>? _liveDistanceKmFuture;

  bool _confirmingCash = false;

  Map<String, dynamic> _paymentMap(Map<String, dynamic> d) {
    final p = d["payment"];
    if (p is Map) return Map<String, dynamic>.from(p as Map);
    return <String, dynamic>{};
  }

  bool _isCash(String method) {
    final m = method.toLowerCase();
    return m.contains("cash");
  }

  bool _cashReceived(String state) {
    final s = state.toLowerCase();
    return s.contains("received") || s.contains("paid");
  }

  String _prettyPayMethod(String method) {
    final m = method.toLowerCase();
    if (m.contains("card")) return "Card";
    if (_isCash(m)) return "Cash";
    return method.isEmpty ? "Payment" : method;
  }

  String _prettyPayState(String method, String state, ProviderBookingStatus bookingStatus) {
    final m = method.toLowerCase();
    final s = state.toLowerCase();
    if (_isCash(m)) {
      if (_cashReceived(s)) return "Received";
      if (bookingStatus == ProviderBookingStatus.completed) return "Awaiting cash";
      return "Pay on service";
    }
    if (s.contains("captur")) return "Captured";
    if (s.contains("await")) return "Awaiting seeker confirm";
    if (s.contains("author") || s.contains("hold")) return "Deposit authorized";
    if (s.isEmpty) return "Pending";
    return state;
  }

  Future<void> _confirmCashReceived(String bookingId) async {
    if (_confirmingCash) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm cash received?"),
        content: const Text("Only confirm if you have received the cash payment from the seeker."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirm")),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _confirmingCash = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable("confirmCashReceived");
      await callable.call({"bookingId": bookingId});
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cash marked as received.")));
    } on FirebaseFunctionsException catch (e) {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Failed to confirm cash.")),
      );
    } catch (_) {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to confirm cash.")));
    } finally {
      if (mounted) setState(() => _confirmingCash = false);
    }
  }

  String? _lastBookingIdForDistance;
  double? _lastBookingLat;
  double? _lastBookingLng;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId);

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.data!.exists) {
              return const Center(child: Text("Booking not found"));
            }

            final b = ProviderBooking.fromDoc(snap.data!);
            final raw = snap.data!.data() ?? <String, dynamic>{};
            final pay = _paymentMap(raw);
            final payMethod = (pay["method"] ?? raw["paymentMethod"] ?? "").toString();
            final payState = (pay["state"] ?? "").toString();
            final needsCashConfirm = b.status == "completed" && _isCash(payMethod) && !_cashReceived(payState);
            final changed = _lastBookingIdForDistance != b.id ||
                _lastBookingLat != b.locationLat ||
                _lastBookingLng != b.locationLng;

            if (changed) {
              _lastBookingIdForDistance = b.id;
              _lastBookingLat = b.locationLat;
              _lastBookingLng = b.locationLng;
              _liveDistanceKmFuture = _computeLiveDistanceToBooking(b);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                children: [
                  // Top bar
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
                      Text(_titleFor(b.status), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _showHistory(context, widget.bookingId),
                        child: const Text("Check Status", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text("Booking ID", style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800)),
                            const Spacer(),
                            Text("#${b.id.substring(0, 6)}", style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 1,
                              child: Text(
                                b.serviceName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2, //
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: ServiceThumb(
                                  model: b,
                                  placeholderBg: KLPalette.mutedBg,
                                  placeholderIconColor: KLPalette.text2,
                                  iconSize: 10,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _kv("Date", _fmtDate(b.scheduledAt)),
                        const SizedBox(height: 6),
                        _kv("Time", _fmtTime(b.scheduledAt)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // About Customer
                  _SectionTitle("About Customer"),
                  const SizedBox(height: 10),
                  _SectionCard(
                    child: Row(
                      children: [
                        const CircleAvatar(radius: 26, backgroundColor: KLPalette.tint50),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.seekerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                              const SizedBox(height: 6),
                              if (b.seekerEmail != null)
                                _meta(Icons.mail_outline, b.seekerEmail!),
                              const SizedBox(height: 6),
                              _meta(Icons.place_outlined, b.locationText),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  _SectionTitle("Location"),
                  const SizedBox(height: 10),
                  _SectionCard(
                    child: SizedBox(
                      height: 200,
                      child: _BookingMapCard(
                        lat: b.locationLat,
                        lng: b.locationLng,
                        label: b.locationText,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  _SectionTitle("Distance"),
                  const SizedBox(height: 10),
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stored distance (provider service ↔ seeker)
                        _row(
                          "Saved distance to seeker",
                          b.distanceKm == null ? "—" : "${b.distanceKm!.toStringAsFixed(1)} km",
                          bold: true,
                        ),
                        const SizedBox(height: 10),

                        // Live distance (provider GPS ↔ seeker)
                        FutureBuilder<double?>(
                          future: _liveDistanceKmFuture,
                          builder: (context, s) {
                            if (s.connectionState == ConnectionState.waiting) {
                              return _row("Live distance to seeker", "Getting GPS...", color: KLPalette.text2);
                            }
                            if (s.hasError) {
                              return _row("Live distance to seeker", "Unavailable", color: KLPalette.text2);
                            }
                            final v = s.data;
                            return _row(
                              "Live distance to seeker",
                              v == null ? "Unavailable" : "${v.toStringAsFixed(1)} km",
                              bold: true,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _liveDistanceKmFuture = _computeLiveDistanceToBooking(b);
                                });
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text("Refresh"),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            )
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Payment details
                  _SectionTitle("Payment Details"),
                  const SizedBox(height: 10),
                  _SectionCard(
                    child: Column(
                      children: [
                        _row("Total Amount", "RM ${b.totalAmount.toStringAsFixed(2)}", bold: true),
                        const SizedBox(height: 10),
                        _row("Method", _prettyPayMethod(payMethod)),
                        const SizedBox(height: 10),
                        _row("Payment", _prettyPayState(payMethod, payState, b.status)),
                        const SizedBox(height: 10),
                        _row("Status", bookingStatusToString(b.status), color: _statusColor(b.status)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Action area
                  if (b.status == ProviderBookingStatus.pending) ...[
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 54,
                            child: FilledButton(
                              onPressed: () => _update(context, b.id, ProviderBookingStatus.accepted),
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
                            height: 54,
                            child: OutlinedButton(
                              onPressed: () => _update(context, b.id, ProviderBookingStatus.declined),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              ),
                              child: const Text("Decline", style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (b.status == ProviderBookingStatus.accepted) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: () => _update(context, b.id, ProviderBookingStatus.completed),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        child: const Text("Mark Completed", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ] else ...[
                    // completed/declined/cancelled read-only (with optional cash confirmation)
                    if (needsCashConfirm) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                        decoration: BoxDecoration(
                          color: KLPalette.mutedBg,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: KLPalette.border),
                        ),
                        child: const Text(
                          "Payment method is Cash. Mark as received after you collect payment from the seeker.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2, height: 1.25),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: _confirmingCash ? null : () => _confirmCashReceived(widget.bookingId),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          child: Text(
                            _confirmingCash ? "Confirming…" : "Mark cash received",
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: KLPalette.mutedBg,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: KLPalette.border),
                        ),
                        child: Text(
                          "This booking is ${bookingStatusToString(b.status)}.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _update(BuildContext context, String bookingId, ProviderBookingStatus s) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await api.updateStatus(bookingId: bookingId, newStatus: s, actorUid: uid);

      if (context.mounted) {
        AppSnack.show(context, "Status updated to ${bookingStatusToString(s)}", type: AppSnackType.success);
      }
    } catch (e) {
      if (context.mounted) {
        AppSnack.show(context,"Update failed: $e", type: AppSnackType.error);
      }
    }
  }

  static String _titleFor(ProviderBookingStatus s) {
    switch (s) {
      case ProviderBookingStatus.all:
        return "—";
      case ProviderBookingStatus.pending:
        return "Pending";
      case ProviderBookingStatus.accepted:
        return "Accepted";
      case ProviderBookingStatus.completed:
        return "Completed";
      case ProviderBookingStatus.declined:
        return "Declined";
      case ProviderBookingStatus.cancelled:
        return "Cancelled";
    }
  }

  static Color _statusColor(ProviderBookingStatus s) {
    switch (s) {
      case ProviderBookingStatus.all:
        return KLPalette.text2;
      case ProviderBookingStatus.completed:
        return const Color(0xFF15803D);
      case ProviderBookingStatus.pending:
        return const Color(0xFFB91C1C);
      case ProviderBookingStatus.accepted:
        return KLPalette.primary700;
      case ProviderBookingStatus.declined:
        return KLPalette.text2;
      case ProviderBookingStatus.cancelled:
        return const Color(0xFFB91C1C);
    }
  }

  static Widget _kv(String k, String v) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text("$k :", style: const TextStyle(fontWeight: FontWeight.w800))),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2)),
      ],
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

  static Widget _row(String l, String r, {bool bold = false, Color? color}) {
    final st = TextStyle(
      fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
      color: color ?? (bold ? KLPalette.text : KLPalette.text2),
    );

    return Row(
      children: [
        Expanded(child: Text(l, style: st)),
        Text(r, style: st),
      ],
    );
  }

  static String _fmtDate(DateTime dt) => "${dt.day}/${dt.month}/${dt.year}";
  static String _fmtTime(DateTime dt) => "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

  void _showHistory(BuildContext context, String bookingId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) {
        final ref = FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .collection('history')
            .orderBy('at', descending: true);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 4, width: 46, decoration: BoxDecoration(color: KLPalette.border, borderRadius: BorderRadius.circular(999))),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text("Booking History", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const Spacer(),
                  Text("ID: #${bookingId.substring(0, 6)}", style: const TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2)),
                ],
              ),
              const SizedBox(height: 12),

              SizedBox(
                height: 340,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ref.snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) return const Center(child: Text("No history yet"));

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final d = docs[i].data();
                        final at = (d['at'] as Timestamp?)?.toDate();
                        final title = (d['title'] ?? 'Update') as String;
                        final sub = (d['subtitle'] ?? '') as String;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 12,
                              width: 12,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: const BoxDecoration(color: KLPalette.primary, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(sub, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                                  if (at != null) ...[
                                    const SizedBox(height: 4),
                                    Text("${at.day}/${at.month}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}",
                                        style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                                  ]
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<double?> _computeLiveDistanceToBooking(ProviderBooking b) async {
    final bookingLat = b.locationLat;
    final bookingLng = b.locationLng;

    if (bookingLat == null || bookingLng == null) return null;

    final pos = await _getCurrentPositionSafely();
    if (pos == null) return null;

    return _haversineKm(pos.latitude, pos.longitude, bookingLat, bookingLng);
  }

  Future<Position?> _getCurrentPositionSafely() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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

}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: child,
      ),
    );
  }
}

class _BookingMapCard extends StatelessWidget {
  final double? lat;
  final double? lng;
  final String label;

  const _BookingMapCard({
    required this.lat,
    required this.lng,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (lat == null || lng == null) {
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

    final pos = LatLng(lat!, lng!);

    return Stack(
      children: [
        Positioned.fill(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProviderFullMapScreen(
                    bookingPos: pos,
                    label: label,
                  ),
                ),
              );
            },
            child: AbsorbPointer(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: pos, zoom: 15),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                liteModeEnabled: true,
                markers: {
                  Marker(markerId: const MarkerId("booking_location"), position: pos),
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
                const SizedBox(width: 8),
                const Icon(Icons.open_in_full, size: 18, color: KLPalette.text2), // optional hint
              ],
            ),
          ),
        ),

        // Navigate button
        Positioned(
          right: 12,
          bottom: 12,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _openGoogleMaps(lat!, lng!),
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
                  Text("Navigate", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
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

class ProviderFullMapScreen extends StatefulWidget {
  final LatLng bookingPos;
  final String label;

  const ProviderFullMapScreen({
    super.key,
    required this.bookingPos,
    required this.label,
  });

  @override
  State<ProviderFullMapScreen> createState() => _ProviderFullMapScreenState();
}

class _ProviderFullMapScreenState extends State<ProviderFullMapScreen> {
  GoogleMapController? _controller;

  LatLng? _providerPos;
  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _startLiveLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _startLiveLocation() async {
    final ok = await _ensureLocationReady();
    if (!ok) return;

    // 1) Get initial position (fast feedback)
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _setProviderPos(LatLng(p.latitude, p.longitude), fit: false);
    } catch (_) {
      // ignore
    }

    // 2) Listen for live updates
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // meters
      ),
    ).listen((p) {
      _setProviderPos(LatLng(p.latitude, p.longitude), fit: false);
    });
  }

  void _setProviderPos(LatLng pos, {required bool fit}) {
    final firstTime = _providerPos == null;
    setState(() => _providerPos = pos);

    // Fit bounds once when we first get provider location
    if (firstTime || fit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  Future<bool> _ensureLocationReady() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId("booking_location"),
        position: widget.bookingPos,
        infoWindow: InfoWindow(title: "Booking Location", snippet: widget.label),
      ),
      if (_providerPos != null)
        Marker(
          markerId: const MarkerId("provider_live"),
          position: _providerPos!,
          infoWindow: const InfoWindow(title: "Your Location"),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
    };

    final pinCount = _providerPos != null ? "2 pins" : "1 pin";

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: widget.bookingPos,
                zoom: 15,
              ),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              liteModeEnabled: false,
              markers: markers,
              onMapCreated: (c) {
                _controller = c;
                _fitBounds(); // if provider already ready, will show both
              },
            ),

            // Top bar
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: KLPalette.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.map_outlined,
                              size: 18, color: KLPalette.text2),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              "Map",
                              style: TextStyle(fontWeight: FontWeight.w900),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            pinCount,
                            style: const TextStyle(
                              color: KLPalette.text2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom actions
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        onPressed: _fitBounds,
                        child: const Text(
                          "Recenter",
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        onPressed: () => _openGoogleMaps(
                          widget.bookingPos.latitude,
                          widget.bookingPos.longitude,
                        ),
                        child: const Text(
                          "Navigate",
                          style: TextStyle(fontWeight: FontWeight.w900),
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
    );
  }

  void _fitBounds() {
    if (_controller == null) return;

    final points = <LatLng>[widget.bookingPos];
    if (_providerPos != null) points.add(_providerPos!);

    if (points.length == 1) {
      _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
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
      final pin = Uri.parse(
        "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
      );
      await launchUrl(pin, mode: LaunchMode.externalApplication);
    }
  }
}

