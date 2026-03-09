import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fyp_flutter/features/pricing/dynamic_pricing.dart';
import 'package:fyp_flutter/core/view_models/service_pricing_vm.dart';
import 'package:fyp_flutter/features/seeker/navigation/seeker_nav_controller.dart';
import 'package:fyp_flutter/core/utils/datetime_slot.dart';
import 'package:fyp_flutter/core/utils/location_area.dart';
import '../../../../core/utils/app_snack.dart';
import 'booking_detail_screen.dart';
import '../../../provider/bookings/data/booking_firestore.dart';
import '../payments/screens/detail_payment_screen.dart';
import '../payments/screens/card_payment_form_screen.dart';
import '../data/seeker_booking_firestore.dart';
import '../../../../core/theme/theme.dart';
import '../../addresses/screens/your_address_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../addresses/data/seeker_address_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../payments/data/payment_method_model.dart';
import '../payments/screens/payment_method_picker_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';

class BookingDetailsScreen extends StatefulWidget {
  final BookedServiceUi service;
  final SeekerNavController nav;

  const BookingDetailsScreen({super.key, required this.service, required this.nav,});

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  PaymentMethodUi selectedPayment = PaymentMethodUi.fromId('cash');

  DateTime selectedDate = DateTime.now();
  List<String> timeSlots = [];
  int selectedTimeIndex = 0;

  int hours = 2;
  int minutes = 0;
  int _maxHoursForSelectedSlot = 2;

  double get hoursTotal => hours + (minutes / 60.0);
  int get totalSelectedMinutes => (hours * 60) + minutes;

  Map<String, _ProviderDayHours> _providerWH = {};
  bool _providerWHLoaded = false;
  String? _scheduleError;


  AddressUiModel? selectedAddress;
  bool _userPickedAddress = false;

  final _addrFs = SeekerAddressFirestore();

  String _preferredPaymentId = 'cash';
  bool _loadedPref = false;
  bool _userPickedPayment = false;

  late DateTime _visibleMonth;

  // Pricing
  double get floorPrice => widget.service.pricing.finalPackage;
  double get perHour => widget.service.hourlyRate;

  double get basePrice => widget.service.basePrice;
  double get discountPercent => widget.service.discountPct;

  int get includedMinutes => (widget.service.durationH * 60) + widget.service.durationM;

  int _remainingMinutesForSelectedSlot = 60;

  double? _distanceKmFor(AddressUiModel? addr) {
    if (addr == null) return null;
    if (widget.service.providerLat == null || widget.service.providerLng == null) return null;
    if (addr.lat == null || addr.lng == null) return null;

    return _haversineKm(
      addr.lat!,
      addr.lng!,
      widget.service.providerLat!,
      widget.service.providerLng!,
    );
  }

  PricingQuote _quoteFor(AddressUiModel? addr) {
    final scheduledAt = combineDateAndSlot(
      selectedDate,
      timeSlots.isEmpty ? "09.00 AM" : timeSlots[selectedTimeIndex],
    );

    return evaluatePricing(
      floorPrice: 0,
      packagePrice: basePrice,
      includedMinutes: includedMinutes,
      hourlyRate: perHour,
      discountPercent: discountPercent,
      ctx: PricingContext(
        scheduledAt: scheduledAt,
        minutes: totalSelectedMinutes,
        distanceKm: _distanceKmFor(addr),
      ),
      rules: widget.service.pricingRules,
      caps: widget.service.pricingCaps,
    );
  }

  DateTime _monthOnly(DateTime d) => DateTime(d.year, d.month);

  DateTime _addMonths(DateTime m, int delta) {
    final y = m.year;
    final mm = m.month + delta;
    return DateTime(y, mm);
  }

  bool _loadingBooked = false;
  List<_BookedRange> _booked = [];

  bool _overlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  bool _isSlotBlocked(DateTime slotStart) {
    final slotEnd = slotStart.add(Duration(minutes: totalSelectedMinutes));
    for (final r in _booked) {
      if (_overlaps(slotStart, slotEnd, r.start, r.end)) return true;
    }
    return false;
  }

  Future<void> _fetchBookedForSelectedDate() async {
    // If provider disabled locking, do nothing
    if (!(widget.service.autoLockTimeSlots)) {
      if (!mounted) return;
      setState(() {
        _booked = [];
        _loadingBooked = false;
      });
      return;
    }

    setState(() => _loadingBooked = true);

    final dayStart = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final snap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: widget.service.providerId)
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(dayEnd))
        .get();

    final out = <_BookedRange>[];

    for (final d in snap.docs) {
      final m = d.data();
      final status = (m['status'] ?? '').toString().toLowerCase();

      // ignore cancelled/declined
      if (status == 'cancelled' || status == 'declined') continue;

      final ts = m['scheduledAt'];
      if (ts is! Timestamp) continue;

      final start = ts.toDate();

      // booking duration stored as hours (double)
      final hRaw = m['hours'];
      final hoursBooked = (hRaw is num) ? hRaw.toDouble() : 1.0;

      final end = start.add(Duration(minutes: (hoursBooked * 60).round()));
      out.add(_BookedRange(start, end));
    }

    if (!mounted) return;
    setState(() {
      _booked = out;
      _loadingBooked = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(selectedDate.year, selectedDate.month);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        backgroundColor: KLPalette.bg,
        body: SafeArea(child: Center(child: Text("Please login"))),
      );
    }

    final providerId = widget.service.providerId;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(providerId).snapshots(),
        builder: (context, provSnap) {
          final provData = provSnap.data?.data() ?? {};
          final wh = (provData['workingHours'] as Map?)?.cast<String, dynamic>();

          if (wh != null) {
            final parsed = <String, _ProviderDayHours>{};

            for (final entry in wh.entries) {
              final v = (entry.value as Map?)?.cast<String, dynamic>();
              if (v == null) continue;

              parsed[entry.key] = _ProviderDayHours(
                enabled: (v['enabled'] ?? false) == true,
                start: _parseHHmm(v['start']?.toString(),
                    fallback: const TimeOfDay(hour: 9, minute: 0)),
                end: _parseHHmm(v['end']?.toString(),
                    fallback: const TimeOfDay(hour: 18, minute: 0)),
              );
            }

            // If first load OR provider changed it, update and rebuild slots
            final changed = !_providerWHLoaded || _providerWH.toString() != parsed.toString();

            if (changed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _providerWH = parsed;
                  _providerWHLoaded = true;
                  _rebuildSlotsForSelectedDate();
                });
                _fetchBookedForSelectedDate();
              });
            }
          }

          if (!provSnap.hasData) {
            return const Scaffold(
              backgroundColor: KLPalette.bg,
              body: SafeArea(child: Center(child: CircularProgressIndicator())),
            );
          }

          return StreamBuilder<AddressUiModel?>(
            stream: _addrFs.streamMainAddress(uid: uid),
            builder: (context, addrSnap) {
              final mainAddr = addrSnap.data;

              // seed selectedAddress once (unless user already picked a different one)
              if (!_userPickedAddress && selectedAddress == null &&
                  mainAddr != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (!_userPickedAddress && selectedAddress == null) {
                    setState(() => selectedAddress = mainAddr);
                  }
                });
              }

              final effectiveAddress = _userPickedAddress
                  ? selectedAddress
                  : (selectedAddress ?? mainAddr);

              final qNow = _quoteFor(effectiveAddress);
              final totalNow = qNow.total;

              final canContinue = effectiveAddress != null &&
                  effectiveAddress.addressLine.trim().isNotEmpty &&
                  timeSlots.isNotEmpty;

              final currentMonth = _monthOnly(DateTime.now());
              final canGoPrev = _monthOnly(_visibleMonth).isAfter(currentMonth);

              return Scaffold(
                backgroundColor: KLPalette.bg,
                body: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _TopBar(
                            title: "Booking Details",
                            onBack: () => Navigator.pop(context),
                            onMenu: () {},
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 18)),

                        SliverToBoxAdapter(
                          child: Text("Select Date",
                              style: Theme
                                  .of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                fontWeight: FontWeight.w900,
                              )),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),

                        SliverToBoxAdapter(
                          child: _CalendarCard(
                            month: _visibleMonth,
                            selected: selectedDate,
                            endsText: _providerEndsTextForSelectedDate(),
                            onPrevMonth: canGoPrev
                                ? () {
                              setState(() {
                                _visibleMonth = _addMonths(_visibleMonth, -1);
                              });
                            }
                                : null,
                            onNextMonth: () {
                              setState(() {
                                _visibleMonth = _addMonths(_visibleMonth, 1);
                              });
                            },
                            onSelect: (d) async {
                              setState(() {
                                selectedDate = d;
                                _visibleMonth = DateTime(d.year, d.month);
                                _rebuildSlotsForSelectedDate();
                              });
                              await _fetchBookedForSelectedDate();
                            },
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 14)),

                        // Working hours row
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _WorkingHoursRow(
                                hours: hours,
                                onMinus: hours <= 1 ? null : () => setState(() {
                                  hours--;
                                  _clampDurationToRemaining();
                                }),
                                onPlus: hours >= _maxHoursForSelectedSlot ? null : () => setState(() {
                                  hours++;
                                  _clampDurationToRemaining();
                                }),
                              ),
                              const SizedBox(height: 12),
                              _MinuteToggle(
                                value: minutes,
                                onChanged: (v) => setState(() {
                                  minutes = v;
                                  _clampDurationToRemaining();
                                }),
                              ),
                            ],
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 18)),

                        SliverToBoxAdapter(
                          child: Text(
                            "Choose Start Time",
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),

                        if (_scheduleError != null) ...[
                          SliverToBoxAdapter(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: KLPalette.mutedBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: KLPalette.border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, size: 18, color: KLPalette.text2),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _scheduleError!,
                                      style: const TextStyle(
                                        color: KLPalette.text2,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        ],

                        if (_loadingBooked)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: LinearProgressIndicator(minHeight: 3),
                            ),
                          ),

                        if (timeSlots.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: List.generate(timeSlots.length, (i) {
                                final selected = i == selectedTimeIndex;
                                final slotStartDt = combineDateAndSlot(selectedDate, timeSlots[i]);
                                final blocked = widget.service.autoLockTimeSlots && _isSlotBlocked(slotStartDt);

                                return _TimeChip(
                                  label: timeSlots[i],
                                  selected: selected && !blocked,
                                  enabled: !blocked,
                                  onTap: blocked
                                      ? null
                                      : () {
                                    setState(() {
                                      selectedTimeIndex = i;
                                      _rebuildSlotsForSelectedDate();
                                    });
                                  },
                                );
                              }),
                            ),
                          ),

                        const SliverToBoxAdapter(child: SizedBox(height: 18)),

                        // Address tile
                        SliverToBoxAdapter(
                          child: _CardSection(
                            title: "Service Address",
                            child: _ListTileCard(
                              icon: Icons.location_on_outlined,
                              title: (effectiveAddress?.title ?? "No address yet"),
                              subtitle: (effectiveAddress?.addressLine ?? "Please add/select an address"),
                              onTap: () async {
                                final initial = effectiveAddress ?? AddressUiModel.demoHome();

                                final result = await Navigator.push<AddressUiModel>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        YourAddressScreen(initial: initial),
                                  ),
                                );
                                if (result != null) {
                                  setState(() {
                                    _userPickedAddress = true;
                                    selectedAddress = result;
                                  });
                                }
                              },
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 14)),

                        SliverToBoxAdapter(
                          child: _CardSection(
                            title: "Payment Method",
                            child: _ListTileCard(
                              icon: Icons.credit_card_rounded,
                              title: selectedPayment.label,
                              subtitle: selectedPayment.subtitle,
                              onTap: () async {
                                final result = await Navigator.push<PaymentMethodUi>(
                                  context,
                                  MaterialPageRoute(builder: (_) => PaymentMethodPickerScreen(initial: selectedPayment)),
                                );
                                if (result != null) {
                                  setState(() {
                                    _userPickedPayment = true;
                                    selectedPayment = result;
                                  });
                                }
                              },
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 14)),

                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // transparent pricing hook
                        SliverToBoxAdapter(
                          child: GestureDetector(
                            onTap: () => _showPriceBreakdown(context, effectiveAddress),
                            child: Row(
                              children: const [
                                Icon(Icons.info_outline, size: 18,
                                    color: KLPalette.text2),
                                SizedBox(width: 8),
                                Text(
                                  "View price breakdown (transparent pricing)",
                                  style: TextStyle(
                                    color: KLPalette.text2,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 130)),
                      ],
                    ),
                  ),
                ),

                // Bottom continue bar
                bottomNavigationBar: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: KLPalette.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        onPressed: canContinue ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  BookingSummaryScreen(
                                    nav: widget.nav,
                                    service: widget.service,
                                    date: selectedDate,
                                    startTime: timeSlots[selectedTimeIndex],
                                    hours: hours,
                                    minutes: minutes,
                                    address: effectiveAddress!,
                                    payment: selectedPayment,
                                    floorPrice: floorPrice,
                                    perHour: perHour,
                                  ),
                            ),
                          );
                        }
                            : null,
                        child: Text(
                          "Continue - ${ServicePricingVM.rm(totalNow, decimals: 2)}",
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPaymentPref();
  }

  Future<void> _loadPaymentPref() async {
    if (_loadedPref) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _loadedPref = true;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final id = (doc.data()?['paymentMethod'] ?? 'cash').toString();

    if (!mounted) return;
    setState(() {
      _preferredPaymentId = id;
      // Set selectedPayment if user hasn't manually changed it
      if (!_userPickedPayment) {
        selectedPayment = PaymentMethodUi.fromId(id);
      }
    });
  }


  void _showPriceBreakdown(BuildContext context, AddressUiModel? addr) {
    final q = _quoteFor(addr);
    final distanceKm = _distanceKmFor(addr);

    final selectedMinutes = totalSelectedMinutes;
    final extraMinutes = (selectedMinutes - includedMinutes).clamp(0, 1 << 30);

    String fmtHM(int mins) {
      final h = mins ~/ 60;
      final m = mins % 60;
      if (m == 0) return "${h}h";
      if (h == 0) return "${m}m";
      return "${h}h ${m}m";
    }

    final extraLabel = extraMinutes <= 0
        ? "Extra time"
        : "Extra time (${fmtHM(extraMinutes)} × RM ${perHour.toStringAsFixed(0)}/hr)";

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
            20, 14, 20, 24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  width: 46,
                  decoration: BoxDecoration(
                    color: KLPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Price breakdown",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
                const SizedBox(height: 12),

                _LineItem(label: "Package price", value: "RM ${basePrice.toStringAsFixed(2)}"),
                _LineItem(label: "Included duration", value: fmtHM(includedMinutes)),
                _LineItem(label: "Selected duration", value: fmtHM(selectedMinutes)),

                if (extraMinutes > 0)
                  _LineItem(
                    label: extraLabel,
                    value: "RM ${q.hoursAmount.toStringAsFixed(2)}",
                  ),

                if (distanceKm != null)
                  _LineItem(
                    label: "Distance",
                    value: "${distanceKm.toStringAsFixed(1)} km",
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Distance-based rules need a saved address with coordinates.",
                        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),

                ...q.lines.map(
                      (l) => _LineItem(
                    label: l.label,
                    value: "${l.amount >= 0 ? '+' : '-'}RM ${l.amount.abs().toStringAsFixed(2)}",
                  ),
                ),

                const Divider(color: KLPalette.border),
                _LineItem(label: "Estimated total", value: ServicePricingVM.rm(q.total, decimals: 2), bold: true),

                const SizedBox(height: 16),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Pricing rules in this service",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 10),

                ...widget.service.pricingRules.map((r) {
                  final applies = _ruleAppliesBooking(
                    rule: r,
                    scheduledAt: combineDateAndSlot(selectedDate, timeSlots.isEmpty ? "09.00 AM" : timeSlots[selectedTimeIndex]),
                    hours: hours,
                    distanceKm: distanceKm,
                  );

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BookingRuleCard(rule: r, appliesNow: applies),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _ruleAppliesBooking({
    required Map<String, dynamic> rule,
    required DateTime scheduledAt,
    required int hours,
    required double? distanceKm,
  }) {
    final id = (rule["id"] ?? "rule").toString();

    final q = evaluatePricing(
      floorPrice: 0,
      packagePrice: basePrice,
      includedMinutes: includedMinutes,
      hourlyRate: perHour,
      discountPercent: discountPercent,
      ctx: PricingContext(
        scheduledAt: scheduledAt,
        minutes: totalSelectedMinutes,
        distanceKm: distanceKm,
      ),
      rules: [rule],
      caps: widget.service.pricingCaps,
    );
    return q.lines.any((l) => l.ruleId == id);
  }

  TimeOfDay _parseHHmm(String? s, {TimeOfDay fallback = const TimeOfDay(hour: 9, minute: 0)}) {
    if (s == null) return fallback;
    final parts = s.split(':');
    if (parts.length != 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return fallback;
    return TimeOfDay(hour: h, minute: m);
  }

  String _weekdayKey(DateTime d) {
    // DateTime.weekday: Mon=1..Sun=7
    switch (d.weekday) {
      case DateTime.monday: return 'mon';
      case DateTime.tuesday: return 'tue';
      case DateTime.wednesday: return 'wed';
      case DateTime.thursday: return 'thu';
      case DateTime.friday: return 'fri';
      case DateTime.saturday: return 'sat';
      case DateTime.sunday: return 'sun';
      default: return 'mon';
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  String _fmtChip(TimeOfDay t) {
    int hour = t.hour;
    final minute = t.minute;
    final isPm = hour >= 12;
    final suffix = isPm ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;

    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    return "$hh.$mm $suffix";
  }

  void _rebuildSlotsForSelectedDate() {
    if (!_providerWHLoaded) return;

    final now = DateTime.now();
    final date = _dateOnly(selectedDate);
    final today = _dateOnly(now);

    // Disallow past date
    if (date.isBefore(today)) {
      timeSlots = [];
      selectedTimeIndex = 0;
      _maxHoursForSelectedSlot = 1;
      hours = 1;
      _scheduleError = "Please select today or a future date.";
      return;
    }

    final key = _weekdayKey(date);
    final dh = _providerWH[key];

    if (dh == null || !dh.enabled) {
      timeSlots = [];
      selectedTimeIndex = 0;
      _maxHoursForSelectedSlot = 1;
      hours = 1;
      _scheduleError = "Provider is not available on this day.";
      return;
    }

    final startMin = _toMinutes(dh.start);
    final endMin = _toMinutes(dh.end);
    final window = endMin - startMin;

    if (window < 60) {
      timeSlots = [];
      selectedTimeIndex = 0;
      _maxHoursForSelectedSlot = 1;
      hours = 1;
      _scheduleError = "Provider working hours too short for booking.";
      return;
    }

    const stepMinutes = 60;
    final slots = <String>[];
    final slotStartMins = <int>[];

    for (int m = startMin; m <= endMin - 60; m += stepMinutes) {
      final dt = DateTime(date.year, date.month, date.day, m ~/ 60, m % 60);

      // If today, must be after current time
      if (date.isAtSameMomentAs(today) || date == today) {
        if (!dt.isAfter(now)) continue; // strict "after now"
      }

      slots.add(_fmtChip(TimeOfDay(hour: m ~/ 60, minute: m % 60)));
      slotStartMins.add(m);
    }

    if (slots.isEmpty) {
      timeSlots = [];
      selectedTimeIndex = 0;
      _maxHoursForSelectedSlot = 1;
      hours = 1;
      _scheduleError = "No available time slots left for today.";
      return;
    }

    timeSlots = slots;
    _scheduleError = null;

    if (selectedTimeIndex >= timeSlots.length) selectedTimeIndex = 0;

    // Recompute max hours based on selected slot
    final selStartMin = slotStartMins[selectedTimeIndex];
    _remainingMinutesForSelectedSlot = (endMin - selStartMin).clamp(0, 24 * 60);
    final maxH = ((endMin - selStartMin) / 60).floor().clamp(1, 24);
    _maxHoursForSelectedSlot = maxH;

    if (hours > _maxHoursForSelectedSlot) hours = _maxHoursForSelectedSlot;
    if (hours < 1) hours = 1;

    const allowedMinutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];
    if (!allowedMinutes.contains(minutes)) minutes = 0;


    final remainingMinutes = (endMin - selStartMin).clamp(0, 24 * 60);
    var selectedTotal = totalSelectedMinutes;

    if (selectedTotal > remainingMinutes) {
      selectedTotal = (remainingMinutes ~/ 5) * 5;

      hours = (selectedTotal ~/ 60).clamp(1, 24);
      minutes = selectedTotal % 60;

      minutes = (minutes ~/ 5) * 5;
    }
  }

  String _providerEndsTextForSelectedDate() {
    if (!_providerWHLoaded) return "—";
    final key = _weekdayKey(_dateOnly(selectedDate));
    final dh = _providerWH[key];
    if (dh == null || !dh.enabled) return "Closed";
    return _fmtHHmm(dh.end);
  }

  String _fmtHHmm(TimeOfDay t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  void _clampDurationToRemaining() {
    const allowedMinutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

    if (!allowedMinutes.contains(minutes)) minutes = 0;

    final remaining = _remainingMinutesForSelectedSlot;
    var selectedTotal = totalSelectedMinutes;

    if (selectedTotal > remaining) {
      selectedTotal = (remaining ~/ 5) * 5;

      final newHours = (selectedTotal ~/ 60);
      final newMinutes = selectedTotal % 60;

      hours = newHours.clamp(1, 24);
      minutes = (newMinutes ~/ 5) * 5;
    }

    _ensureSelectedSlotNotBlocked();
  }

  void _ensureSelectedSlotNotBlocked() {
    if (!widget.service.autoLockTimeSlots) return;
    if (timeSlots.isEmpty) return;

    final slotStart = combineDateAndSlot(selectedDate, timeSlots[selectedTimeIndex]);
    if (!_isSlotBlocked(slotStart)) return;

    // find first unblocked slot
    for (int i = 0; i < timeSlots.length; i++) {
      final s = combineDateAndSlot(selectedDate, timeSlots[i]);
      if (!_isSlotBlocked(s)) {
        selectedTimeIndex = i;
        _rebuildSlotsForSelectedDate();
        return;
      }
    }

    // if all blocked, clear list (or show message)
    timeSlots = [];
    selectedTimeIndex = 0;
    _scheduleError = "No available time slots for the selected duration.";
  }
}

class _BookingRuleCard extends StatelessWidget {
  final Map<String, dynamic> rule;
  final bool appliesNow;

  const _BookingRuleCard({required this.rule, required this.appliesNow});

  @override
  Widget build(BuildContext context) {
    final label = (rule["label"] ?? rule["id"] ?? "Rule").toString();
    final when = (rule["when"] as Map?)?.cast<String, dynamic>() ?? const {};
    final desc = _describeWhen(when);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              appliesNow ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
              color: appliesNow ? KLPalette.primary : KLPalette.text2,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: appliesNow ? KLPalette.tint50 : KLPalette.mutedBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: KLPalette.border),
              ),
              child: Text(
                appliesNow ? "Applied" : "Not now",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: appliesNow ? KLPalette.primary : KLPalette.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _describeWhen(Map<String, dynamic> when) {
    final parts = <String>[];

    final days = (when["days"] as List?)?.cast<dynamic>().map((e) => (e as num).toInt()).toList();
    if (days != null && days.isNotEmpty) {
      final isWeekend = days.contains(6) && days.contains(7) && days.length == 2;
      parts.add(isWeekend ? "Weekends" : "Days: ${days.join(', ')}");
    }

    final sh = (when["startHour"] as num?)?.toInt();
    final eh = (when["endHour"] as num?)?.toInt();
    if (sh != null && eh != null) {
      parts.add("Time: ${sh.toString().padLeft(2,'0')}:00–${eh.toString().padLeft(2,'0')}:59");
    }

    final minD = (when["minDistanceKm"] as num?)?.toDouble();
    if (minD != null) {
      parts.add("Distance ≥ ${minD.toStringAsFixed(0)} km");
    }

    return parts.isEmpty ? "Always applies" : parts.join(" • ");
  }
}

class _ProviderDayHours {
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;
  const _ProviderDayHours({
    required this.enabled,
    required this.start,
    required this.end,
  });
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onMenu;

  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back, onTap: onBack),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const Spacer(),
        const SizedBox(width: 48),
        //_CircleButton(icon: Icons.more_horiz, onTap: onMenu),
      ],
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

class _CalendarCard extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;
  final String endsText;

  const _CalendarCard({
    required this.month,
    required this.selected,
    required this.onSelect,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.endsText,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = (first.weekday % 7); // Sun=0, Mon=1..Sat=6

    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final dateOnly = DateTime(date.year, date.month, date.day);

      final isSelected =
          date.year == selected.year && date.month == selected.month && date.day == selected.day;

      final isPastDay = dateOnly.isBefore(todayOnly);

      cells.add(_DayCell(
        day: d,
        selected: isSelected,
        enabled: !isPastDay,
        onTap: isPastDay ? null : () => onSelect(date),
      ));
    }

    final prevDisabled = onPrevMonth == null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: onPrevMonth,
                  borderRadius: BorderRadius.circular(999),
                  child: Opacity(
                    opacity: prevDisabled ? 0.35 : 1.0,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.chevron_left_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  "${_monthName(month.month)} ${month.year}",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const Spacer(),
                InkWell(
                  onTap: onNextMonth,
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _WeekHeader(),
            const SizedBox(height: 12),

            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 6,
              children: cells,
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                const Text("Ends",
                    style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: KLPalette.mutedBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KLPalette.border),
                  ),
                  child: Text(endsText, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader();

  @override
  Widget build(BuildContext context) {
    const labels = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels
          .map((s) => SizedBox(
        width: 36,
        child: Text(
          s,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: KLPalette.text2,
            fontWeight: FontWeight.w900,
          ),
        ),
      ))
          .toList(),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (day == 0) return const SizedBox.shrink();

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: selected ? KLPalette.tint50 : Colors.transparent,
              shape: BoxShape.circle,
              border: selected ? Border.all(color: KLPalette.primary) : null,
            ),
            child: Center(
              child: Text(
                "$day",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: selected ? 22 : 20,
                  color: selected ? KLPalette.primary : KLPalette.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkingHoursRow extends StatelessWidget {
  final int hours;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _WorkingHoursRow({
    required this.hours,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time_rounded, color: KLPalette.text),
            const SizedBox(width: 12),
            const Text("Working Hours", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const Spacer(),
            _RoundIcon(
              icon: Icons.remove,
              onTap: onMinus,
              filled: false,
            ),
            const SizedBox(width: 14),
            Text("$hours", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(width: 14),
            _RoundIcon(
              icon: Icons.add,
              onTap: onPlus,
              filled: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _MinuteToggle extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _MinuteToggle({
    required this.value,
    required this.onChanged,
  });

  static const List<int> options = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

  @override
  Widget build(BuildContext context) {
    String labelFor(int m) => m.toString().padLeft(2, '0');

    final safeValue = options.contains(value) ? value : 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined, color: KLPalette.text),
            const SizedBox(width: 12),
            const Text(
              "Minutes",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 12),

            /// Scrollable chips
            Expanded(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final m = options[index];
                    final selected = m == safeValue;

                    return GestureDetector(
                      onTap: () => onChanged(m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? KLPalette.primary
                              : KLPalette.mutedBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? KLPalette.primary
                                : KLPalette.border,
                          ),
                        ),
                        child: Text(
                          labelFor(m),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: selected
                                ? Colors.white
                                : KLPalette.text,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  const _RoundIcon({
    required this.icon,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: filled ? KLPalette.primary : KLPalette.bg,
            shape: BoxShape.circle,
            border: Border.all(color: KLPalette.border),
          ),
          child: Icon(icon, color: filled ? Colors.white : KLPalette.text),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _TimeChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? KLPalette.primary : KLPalette.bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: enabled ? KLPalette.border : KLPalette.border.withOpacity(0.4),
            ),
          ),
          child: Text(
            enabled ? label : label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: selected ? Colors.white : KLPalette.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _CardSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ListTileCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ListTileCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: KLPalette.mutedBg,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: Icon(icon, color: KLPalette.text),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, color: KLPalette.text2),
          ],
        ),
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _LineItem({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
      fontSize: bold ? 16 : 14,
      color: bold ? KLPalette.text : KLPalette.text2,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

String _monthName(int m) {
  const names = [
    "January","February","March","April","May","June",
    "July","August","September","October","November","December"
  ];
  return names[(m - 1).clamp(0, 11)];
}

enum VoucherType { percent, fixed }

class VoucherUi {
  final String id;
  final String title;
  final String subtitle;
  final VoucherType type; // percent / fixed
  final double value;

  const VoucherUi({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.value,
  });
}

class VoucherScreen extends StatefulWidget {
  final VoucherUi? selected;
  const VoucherScreen({super.key, required this.selected});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  VoucherUi? picked;

  final vouchers = const [
    VoucherUi(
      id: "v10",
      title: "10% OFF",
      subtitle: "Min spend RM 50",
      type: VoucherType.percent,
      value: 10,
    ),
    VoucherUi(
      id: "v5",
      title: "RM 5 OFF",
      subtitle: "No minimum spend",
      type: VoucherType.fixed,
      value: 5,
    ),
    VoucherUi(
      id: "v20",
      title: "20% OFF",
      subtitle: "Min spend RM 120",
      type: VoucherType.percent,
      value: 20,
    ),
  ];

  @override
  void initState() {
    super.initState();
    picked = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            children: [
              _TopBar(
                title: "Vouchers",
                onBack: () => Navigator.pop(context),
                onMenu: () {},
              ),
              const SizedBox(height: 18),

              Expanded(
                child: ListView.separated(
                  itemCount: vouchers.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      final isSelected = picked == null;
                      return InkWell(
                        onTap: () => setState(() => picked = null),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: KLPalette.bg,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isSelected ? KLPalette.primary : KLPalette.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.block_rounded, color: KLPalette.text2),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text("No voucher", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              ),
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                                color: isSelected ? KLPalette.primary : KLPalette.text2,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final v = vouchers[i - 1];
                    final isSelected = picked?.id == v.id;

                    return InkWell(
                      onTap: () => setState(() => picked = v),
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: KLPalette.bg,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isSelected ? KLPalette.primary : KLPalette.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              height: 44,
                              width: 44,
                              decoration: BoxDecoration(
                                color: KLPalette.mutedBg,
                                shape: BoxShape.circle,
                                border: Border.all(color: KLPalette.border),
                              ),
                              child: const Icon(Icons.percent_rounded, color: KLPalette.text),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(v.subtitle, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                              color: isSelected ? KLPalette.primary : KLPalette.text2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KLPalette.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: () => Navigator.pop(context, picked),
                  child: const Text("Apply", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookingSummaryScreen extends StatelessWidget {
  final SeekerNavController nav;
  final BookedServiceUi service;
  final DateTime date;
  final String startTime;
  final int hours;
  final int minutes;
  final AddressUiModel address;
  final PaymentMethodUi payment;
  final double floorPrice;
  final double perHour;

  const BookingSummaryScreen({
    super.key,
    required this.nav,
    required this.service,
    required this.date,
    required this.startTime,
    required this.hours,
    required this.minutes,
    required this.address,
    required this.payment,
    required this.floorPrice,
    required this.perHour,
  });

  int get totalSelectedMinutes => (hours * 60) + minutes;

  double get hoursTotal => hours + (minutes / 60.0);

  @override
  Widget build(BuildContext context) {
    final dateText = "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year}";

    final scheduledAt = combineDateAndSlot(date, startTime);

    final pricing = service.pricing;
    final floorPrice = pricing.finalPackage;
    final perHour = service.hourlyRate;

    final distanceKm = (service.providerLat != null &&
        service.providerLng != null &&
        address.lat != null &&
        address.lng != null)
        ? _haversineKm(address.lat!, address.lng!, service.providerLat!, service.providerLng!)
        : null;

    final includedMinutes = (service.durationH * 60) + service.durationM;
    final packagePrice = service.pricing.finalPackage;

    final q = evaluatePricing(
      floorPrice: 0,
      packagePrice: service.basePrice,          // raw package price
      includedMinutes: includedMinutes,
      hourlyRate: perHour,          // extra-hour rate
      discountPercent: service.discountPct,
      ctx: PricingContext(
        scheduledAt: scheduledAt,
        minutes: totalSelectedMinutes,
        distanceKm: distanceKm,
      ),
      rules: service.pricingRules,
      caps: service.pricingCaps,
    );

    final pricingLines = q.lines.map((l) => {
      "ruleId": l.ruleId,
      "label": l.label,
      "amount": l.amount,
    }).toList();

    final pricingRulesSnapshot = service.pricingRules;

    final discountedPackage =
        service.basePrice * (1.0 - (service.discountPct.clamp(0, 100) / 100.0));

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: ListView(
            children: [
              _TopBar(
                title: "Booking Summary",
                onBack: () => Navigator.pop(context),
                onMenu: () {},
              ),
              const SizedBox(height: 18),

              _CardSection(
                title: "Schedule",
                child: Column(
                  children: [
                    _LineItem(label: "Date", value: dateText),
                    _LineItem(label: "Start time", value: startTime),
                    _LineItem(label: "Duration", value: fmtHM(totalSelectedMinutes)),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _CardSection(
                title: "Service Address",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(address.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(address.addressLine, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _CardSection(
                title: "Payment",
                child: _LineItem(label: payment.label, value: payment.subtitle),
              ),

              const SizedBox(height: 14),

              _CardSection(
                title: "Price",
                child: Column(
                  children: [
                    if (pricing.discountPct > 0) ...[
                      _LineItem(label: "Base price", value: ServicePricingVM.rm(pricing.basePrice, decimals: 2)),
                      _LineItem(label: "Discount", value: "-${pricing.discountPct.toStringAsFixed(0)}%"),
                      _LineItem(label: "After discount", value: ServicePricingVM.rm(discountedPackage, decimals: 2)),
                    ] else
                      _LineItem(label: "Floor price", value: ServicePricingVM.rm(floorPrice, decimals: 2)),
                    _LineItem(
                      label: "Working hours (${fmtHM(totalSelectedMinutes)} × RM ${perHour.toStringAsFixed(0)}/hr)",
                      value: ServicePricingVM.rm(q.hoursAmount, decimals: 2),
                    ),

                    // Rule lines
                    ...q.lines.map((l) => _LineItem(
                      label: l.label,
                      value: "${l.amount >= 0 ? '+' : '-'}${ServicePricingVM.rm(l.amount.abs(), decimals: 2)}",
                    )),

                    const Divider(color: KLPalette.border),
                    _LineItem(label: "Total", value: ServicePricingVM.rm(q.total, decimals: 2), bold: true),
                  ],
                ),
              ),

              const SizedBox(height: 130),
            ],
          ),
        ),
      ),

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

              onPressed: () async {
                final scheduledAt = combineDateAndSlot(date, startTime);

                final locationText = address.addressLine;
                final locationArea = LocationArea.fromLocationText(locationText);

                try {
                  final auth = FirebaseAuth.instance.currentUser;
                  if (auth == null) throw Exception('Not logged in');

                  // --- Card payment simulation (collect card details before creating booking) ---
                  final methodId = payment.id.toString();
                  final isCard = methodId.toLowerCase() == 'card' || methodId.toLowerCase().contains('card');
                  // Map<String, dynamic>? paymentMeta;
                  // if (isCard) {
                  //   final meta = await Navigator.push<Map<String, dynamic>>(
                  //     context,
                  //     MaterialPageRoute(
                  //       builder: (_) => CardPaymentFormScreen(amount: q.total),
                  //     ),
                  //   );
                  //   if (meta == null) return; // cancelled
                  //   paymentMeta = meta;
                  // }

                  // Loading dialog while calling Cloud Function
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator()),
                  );

                  // Callable
                  final callable = FirebaseFunctions.instance.httpsCallable('createBookingVerified');

                  final res = await callable.call({
                    "serviceId": service.id,
                    "providerId": service.providerId,
                    "scheduledAtMs": scheduledAt.millisecondsSinceEpoch,
                    "hours": hoursTotal,

                    "addressId": address.id,
                    "locationText": locationText,
                    "locationArea": locationArea,
                    "locationLat": address.lat,
                    "locationLng": address.lng,
                    "locationGeohash": address.geohash,

                    "paymentMethodId": methodId,
                    //if (paymentMeta != null) "paymentMeta": paymentMeta,
                  });

                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }

                  final data = (res.data as Map);
                  final bookingId = data["bookingId"] as String;
                  final totalAmount = (data["totalAmount"] as num).toDouble();

                  if (!context.mounted) return;

                  final action = await showDialog<_BookingSuccessAction>(
                    context: context,
                    barrierDismissible: true,
                    builder: (dialogContext) => _BookingSuccessDialog(
                      onViewReceipt: () => Navigator.pop(dialogContext, _BookingSuccessAction.viewReceipt),
                      onMessageWorkers: () => Navigator.pop(dialogContext, _BookingSuccessAction.messageWorkers),
                      subtitle: isCard
                          ? "Request sent. You will pay after the provider accepts your booking."
                          : "Request sent. You will pay in cash during/after the service.",
                    ),
                  );

                  if (!context.mounted) return;

                  if (action == _BookingSuccessAction.viewReceipt) {
                    // final heroUrl = await fetchServiceHeroUrl(service.id);
                    // if (!context.mounted) return;
                    //
                    // Navigator.push(
                    //   context,
                    //   MaterialPageRoute(
                    //     builder: (_) => DetailPaymentScreen(
                    //       nav: nav,
                    //       serviceTitle: service.title,
                    //       rating: service.rating,
                    //       locationText: service.location,
                    //       paymentMethod: payment.label,
                    //       date: date,
                    //       startTime: startTime,
                    //       transactionId: bookingId,
                    //       totalAmount: totalAmount,
                    //       serviceImageUrl: heroUrl,
                    //     ),
                    //   ),
                    // );

                    nav.goBookings(BookingsFilter.upcoming);

                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => BookingDetailScreen(
                          bookingId: bookingId,
                          nav: nav,
                        ),
                      ),
                          (route) => route.isFirst,
                    );
                  } else if (action == _BookingSuccessAction.messageWorkers) {
                    nav.goChatWith(service.providerId);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  } else {
                    nav.goBookings();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                } on FirebaseFunctionsException catch (e) {
                  if (Navigator.of(context, rootNavigator: true).canPop()) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                  if (!context.mounted) return;
                  AppSnack.show(
                    context,
                    e.message ?? "Booking failed (${e.code})",
                    type: AppSnackType.error,
                  );
                } catch (e) {
                  if (Navigator.of(context, rootNavigator: true).canPop()) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                  if (!context.mounted) return;
                  AppSnack.show(
                    context,
                    "Booking failed: $e",
                    type: AppSnackType.error,
                  );
                }
              },

              child: Text(
                "Confirm - ${ServicePricingVM.rm(q.total, decimals: 2)}",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String fmtHM(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return "${h}h";
    if (h == 0) return "${m}m";
    return "${h}h ${m}m";
  }
}

enum _BookingSuccessAction { viewReceipt, messageWorkers }

class _BookingSuccessDialog extends StatelessWidget {
  final VoidCallback onViewReceipt;
  final VoidCallback onMessageWorkers;
  final String subtitle;

  const _BookingSuccessDialog({
    required this.onViewReceipt,
    required this.onMessageWorkers,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 26),
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          decoration: BoxDecoration(
            color: KLPalette.bg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: KLPalette.border),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                spreadRadius: 2,
                offset: Offset(0, 10),
                color: Color(0x1A000000),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 72,
                width: 72,
                decoration: BoxDecoration(
                  color: KLPalette.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 42),
              ),
              const SizedBox(height: 16),
              const Text(
                "Booking Successful",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KLPalette.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: onViewReceipt,
                  child: const Text(
                    "View Booking Details",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: KLPalette.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: onMessageWorkers,
                  child: const Text(
                    "Message Workers",
                    style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text),
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

class BookedServiceUi {
  final String id;
  final String providerId;
  final String title;
  final String location;
  final double rating;
  final double basePrice;
  final double discountPct;
  final double floorPrice;
  final double hourlyRate;
  final int durationH;
  final int durationM;
  final List<Map<String, dynamic>> pricingRules;
  final Map<String, dynamic>? pricingCaps;
  final double? providerLat;
  final double? providerLng;
  final bool autoLockTimeSlots;

  const BookedServiceUi({
    required this.id,
    required this.providerId,
    required this.title,
    required this.location,
    required this.rating,
    required this.basePrice,
    required this.discountPct,
    required this.floorPrice,
    required this.hourlyRate,
    required this.durationH,
    required this.durationM,
    required this.pricingRules,
    required this.pricingCaps,
    required this.providerLat,
    required this.providerLng,
    this.autoLockTimeSlots = true,
  });

  ServicePricingVM get pricing {
    return ServicePricingVM.fromBookedService(this);
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

class _BookedRange {
  final DateTime start;
  final DateTime end;
  _BookedRange(this.start, this.end);
}