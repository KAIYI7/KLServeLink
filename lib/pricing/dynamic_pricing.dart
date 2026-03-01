class PricingLine {
  final String label;
  final double amount;
  final String ruleId;
  final String? note;
  const PricingLine({required this.label, required this.amount, required this.ruleId, this.note});
}

class PricingQuote {
  final double baseFloor;
  final double hourlyRate;
  final int minutes;
  final double hoursAmount;
  final double rulesDelta;
  final double total;
  final List<PricingLine> lines;

  const PricingQuote({
    required this.baseFloor,
    required this.hourlyRate,
    required this.minutes,
    required this.hoursAmount,
    required this.rulesDelta,
    required this.total,
    required this.lines,
  });

  double get hoursExact => minutes / 60.0;
}

class PricingContext {
  final DateTime scheduledAt;
  final int minutes;
  final double? distanceKm;

  const PricingContext({
    required this.scheduledAt,
    required this.minutes,
    required this.distanceKm,
  });

  double get hoursExact => minutes / 60.0;
}

PricingQuote evaluatePricing({
  required double floorPrice,
  required double packagePrice,
  required int includedMinutes,
  required double hourlyRate,
  required double discountPercent,
  required PricingContext ctx,
  required List<Map<String, dynamic>> rules,
  Map<String, dynamic>? caps,
}) {
  final extraMinutes = (ctx.minutes - includedMinutes).clamp(0, 1 << 30);
  final extraHours = extraMinutes / 60.0;

  final baseBeforeDiscount = floorPrice + packagePrice + (extraHours * hourlyRate);
  final lines = <PricingLine>[];

  final discountAmount = discountPercent > 0
      ? -(baseBeforeDiscount * (discountPercent / 100.0))
      : 0.0;

  final baseAfterDiscount = baseBeforeDiscount + discountAmount;

  if (discountAmount.abs() > 0.0001) {
    lines.add(const PricingLine(
      label: "Service discount",
      amount: 0, // placeholder, replaced below
      ruleId: "__BASE_DISCOUNT__",
    ));
    // Replace the last line with correct amount (Dart const limitation workaround)
    lines.removeLast();
    lines.add(PricingLine(
      label: "Service discount",
      amount: discountAmount,
      ruleId: "__BASE_DISCOUNT__",
    ));
  }

  // caps
  double _capNum(String k, double fallback) =>
      ((caps?[k] as num?)?.toDouble()) ?? fallback;

  final maxPercentLegacy = _capNum("maxPercent", 50.0);
  final maxFixedLegacy = _capNum("maxFixed", 30.0);

  final maxSurchargePercent = _capNum("maxSurchargePercent", maxPercentLegacy);
  final maxDiscountPercent  = _capNum("maxDiscountPercent",  maxPercentLegacy);

  final maxSurchargeFixed = _capNum("maxSurchargeFixed", maxFixedLegacy);
  final maxDiscountFixed  = _capNum("maxDiscountFixed",  maxFixedLegacy);

  final minTotal = _capNum("minTotal", 0.0);
  final maxTotal = _capNum("maxTotal", 1e12);

  bool dayMatch(Map<String, dynamic> when) {
    final days = (when["days"] as List?)
        ?.cast<dynamic>()
        .map((e) => (e as num).toInt())
        .toList();
    if (days == null || days.isEmpty) return true;
    return days.contains(ctx.scheduledAt.weekday);
  }

  bool timeMatch(Map<String, dynamic> when) {
    final startHour = (when["startHour"] as num?)?.toInt();
    final endHour = (when["endHour"] as num?)?.toInt();
    if (startHour == null || endHour == null) return true;

    final h = ctx.scheduledAt.hour;

    // Normal window: 9..18
    if (startHour <= endHour) return h >= startHour && h <= endHour;

    // Overnight window: 22..6 => (h >= 22) OR (h <= 6)
    return h >= startHour || h <= endHour;
  }

  bool hoursMatch(Map<String, dynamic> when) {
    final minH = (when["minHours"] as num?)?.toDouble();
    final maxH = (when["maxHours"] as num?)?.toDouble();
    final h = ctx.hoursExact;

    if (minH != null && h < minH) return false;
    if (maxH != null && h > maxH) return false;
    return true;
  }

  bool distanceMatch(Map<String, dynamic> when) {
    final minD = (when["minDistanceKm"] as num?)?.toDouble();
    final maxD = (when["maxDistanceKm"] as num?)?.toDouble();
    final d = ctx.distanceKm;

    if (minD == null && maxD == null) return true;
    if (d == null) return false;

    if (minD != null && d < minD) return false;
    if (maxD != null && d > maxD) return false;
    return true;
  }

  bool leadTimeMatch(Map<String, dynamic> when) {
    final minLeadHours = (when["minLeadHours"] as num?)?.toInt();
    if (minLeadHours == null) return true;
    final now = DateTime.now();
    return ctx.scheduledAt.difference(now).inHours >= minLeadHours;
  }

  DateTime? _parseIsoDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    // Expect YYYY-MM-DD
    final parts = s.split("-");
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  bool dateRangeMatch(Map<String, dynamic> when) {
    final start = _parseIsoDate(when["startDate"]);
    final end = _parseIsoDate(when["endDate"]);
    if (start == null && end == null) return true;

    final day = DateTime(ctx.scheduledAt.year, ctx.scheduledAt.month, ctx.scheduledAt.day);
    if (start != null) {
      final sDay = DateTime(start.year, start.month, start.day);
      if (day.isBefore(sDay)) return false;
    }
    if (end != null) {
      final eDay = DateTime(end.year, end.month, end.day);
      if (day.isAfter(eDay)) return false;
    }
    return true;
  }

  bool matches(Map<String, dynamic> when) {
    return dayMatch(when) &&
        timeMatch(when) &&
        hoursMatch(when) &&
        distanceMatch(when) &&
        leadTimeMatch(when) &&
        dateRangeMatch(when);
  }

  double clampPercent(double v) {
    if (v >= 0) return v.clamp(0.0, maxSurchargePercent).toDouble();
    return v.clamp(-maxDiscountPercent, 0.0).toDouble();
  }

  double clampFixed(double v) {
    if (v >= 0) return v.clamp(0.0, maxSurchargeFixed).toDouble();
    return v.clamp(-maxDiscountFixed, 0.0).toDouble();
  }

  final allRules = <Map<String, dynamic>>[
    ...rules,
  ];

  // apply rules with priority + exclusive groups
  final sorted = [...allRules]..sort((a, b) {
    final pa = (a["priority"] as num?)?.toInt() ?? 0;
    final pb = (b["priority"] as num?)?.toInt() ?? 0;
    return pb.compareTo(pa); // high first
  });


  final usedExclusiveGroups = <String>{};
  double delta = 0;

  for (final r in sorted) {
    final id = (r["id"] ?? "rule").toString();
    final label = (r["label"] ?? id).toString();
    final type = (r["type"] ?? "").toString(); // "percent" | "fixed"
    final value = (r["value"] is num) ? (r["value"] as num).toDouble() : 0.0;
    final when = (r["when"] as Map?)?.cast<String, dynamic>() ?? const {};

    if (!matches(when)) continue;

    final group = (r["exclusiveGroup"] ?? "").toString().trim();
    if (group.isNotEmpty && usedExclusiveGroups.contains(group)) {
      continue;
    }

    double amt = 0.0;
    String? note;
    if (type == "percent") {
      final capped = clampPercent(value);
      amt = baseAfterDiscount * (capped / 100.0);

      if ((capped - value).abs() > 0.0001) {
        note =
        "Capped: ${value.toStringAsFixed(0)}% → ${capped.toStringAsFixed(0)}%";
      }

    } else if (type == "fixed") {
      final capped = clampFixed(value);
      amt = capped;

      if ((capped - value).abs() > 0.0001) {
        note =
        "Capped: RM ${value.toStringAsFixed(2)} → RM ${capped.toStringAsFixed(2)}";
      }
    } else {
      continue;
    }

    if (amt.abs() > 0.0001) {
      delta += amt;
      lines.add(PricingLine(label: label, amount: amt, ruleId: id, note: note));
      if (group.isNotEmpty) usedExclusiveGroups.add(group);
    }
  }

  final rawTotal = baseAfterDiscount + delta;
  final total = rawTotal.clamp(minTotal, maxTotal).toDouble();

  if ((total - rawTotal).abs() > 0.0001) {
    final direction = (total > rawTotal) ? "Raised" : "Lowered";
    lines.add(PricingLine(
      label: "Total adjusted by caps",
      amount: total - rawTotal,
      ruleId: "__TOTAL_CAP__",
      note: "$direction to RM ${total.toStringAsFixed(2)}",
    ));
  }

  return PricingQuote(
    baseFloor: floorPrice,
    hourlyRate: hourlyRate,
    minutes: ctx.minutes,
    hoursAmount: extraHours * hourlyRate,
    rulesDelta: delta,
    total: total,
    lines: lines,
  );
}