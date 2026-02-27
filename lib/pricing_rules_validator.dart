import 'dart:math' as math;

class PricingRulesValidator {
  static List<String> validate(List<Map<String, dynamic>> rules) {
    final errors = <String>[];

    // Normalize & categorize
    final normalized = rules.map(_normalizeRule).toList();

    // Global rules (no constraints) - only one
    final globals = normalized.where((r) => _category(r) == _RuleCat.global).toList();
    if (globals.length > 1) {
      errors.add("Only one 'global' rule (no conditions) is allowed.");
    }

    // Distance rules - only one if range isn't supported
    final distance = normalized.where((r) => _category(r) == _RuleCat.distance).toList();
    if (distance.length > 1) {
      errors.add("Only one distance-based rule is allowed (to avoid stacking).");
    }

    // Duration rules - only one if range isn't supported
    final duration = normalized.where((r) => _category(r) == _RuleCat.duration).toList();
    if (duration.length > 1) {
      errors.add("Only one duration-based rule is allowed (to avoid stacking).");
    }

    // Time rules - no overlaps
    final timeRules = normalized.where((r) => _category(r) == _RuleCat.time).toList();
    for (int i = 0; i < timeRules.length; i++) {
      for (int j = i + 1; j < timeRules.length; j++) {
        if (_timeOverlaps(timeRules[i], timeRules[j])) {
          final a = _label(timeRules[i]);
          final b = _label(timeRules[j]);
          errors.add("Time rules overlap: '$a' conflicts with '$b'. Please adjust day/time ranges.");
        }
      }
    }

    // Exact duplicates (same type/value/when signature)
    final seen = <String>{};
    for (final r in normalized) {
      final sig = _signature(r);
      if (seen.contains(sig)) {
        errors.add("Duplicate rule detected: '${_label(r)}'.");
      }
      seen.add(sig);
    }

    return errors;
  }

  /// Auto-assign exclusive groups consistently
  static List<Map<String, dynamic>> autoAssignExclusiveGroups(List<Map<String, dynamic>> rules) {
    return rules.map((raw) {
      final r = Map<String, dynamic>.from(raw);
      final cat = _category(_normalizeRule(r));
      r["exclusiveGroup"] = switch (cat) {
        _RuleCat.time => "time",
        _RuleCat.distance => "distance",
        _RuleCat.duration => "duration",
        _RuleCat.global => "global",
        _RuleCat.other => (r["exclusiveGroup"] ?? "other"),
      };
      return r;
    }).toList();
  }


  static Map<String, dynamic> _normalizeRule(Map<String, dynamic> raw) {
    final r = Map<String, dynamic>.from(raw);
    r["id"] = (r["id"] ?? "rule").toString();
    r["type"] = (r["type"] ?? "fixed").toString(); // "fixed" or "percent"
    r["value"] = (r["value"] is num) ? (r["value"] as num).toDouble() : 0.0;
    final when = (r["when"] is Map) ? Map<String, dynamic>.from(r["when"]) : <String, dynamic>{};
    r["when"] = when;
    return r;
  }

  static String _label(Map<String, dynamic> r) =>
      (r["label"] ?? r["id"] ?? "Rule").toString();

  static String _signature(Map<String, dynamic> r) {
    final when = (r["when"] as Map).cast<String, dynamic>();
    final days = (when["days"] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [];
    final sh = when["startHour"];
    final eh = when["endHour"];
    final minD = when["minDistanceKm"];
    final minM = when["minMinutes"] ?? when["minutes"] ?? when["minDurationMinutes"];
    return [
      r["type"].toString(),
      (r["value"] as double).toStringAsFixed(4),
      "days=${days.join(",")}",
      "sh=$sh",
      "eh=$eh",
      "minD=$minD",
      "minM=$minM",
    ].join("|");
  }

  static _RuleCat _category(Map<String, dynamic> r) {
    final when = (r["when"] as Map).cast<String, dynamic>();

    final hasDays = when["days"] is List && (when["days"] as List).isNotEmpty;
    final hasTime = when["startHour"] != null || when["endHour"] != null;
    if (hasDays || hasTime) return _RuleCat.time;

    if (when["minDistanceKm"] != null || when["maxDistanceKm"] != null) return _RuleCat.distance;

    if (when["minMinutes"] != null || when["maxMinutes"] != null ||
        when["minutes"] != null || when["minDurationMinutes"] != null) {
      return _RuleCat.duration;
    }

    // No conditions at all
    if (when.isEmpty) return _RuleCat.global;

    return _RuleCat.other;
  }

  static bool _timeOverlaps(Map<String, dynamic> a, Map<String, dynamic> b) {
    final wa = (a["when"] as Map).cast<String, dynamic>();
    final wb = (b["when"] as Map).cast<String, dynamic>();

    final da = (wa["days"] as List?)?.map((e) => (e as num).toInt()).toSet()
        ?? {1,2,3,4,5,6,7};
    final db = (wb["days"] as List?)?.map((e) => (e as num).toInt()).toSet()
        ?? {1,2,3,4,5,6,7};

    // days overlap?
    final dayOverlap = da.intersection(db).isNotEmpty;
    if (!dayOverlap) return false;

    final sa = (wa["startHour"] is num) ? (wa["startHour"] as num).toInt() : 0;
    final ea = (wa["endHour"] is num) ? (wa["endHour"] as num).toInt() : 23;
    final sb = (wb["startHour"] is num) ? (wb["startHour"] as num).toInt() : 0;
    final eb = (wb["endHour"] is num) ? (wb["endHour"] as num).toInt() : 23;

    final start = math.max(sa, sb);
    final end = math.min(ea, eb);

    // inclusive overlap
    return start <= end;
  }
}

enum _RuleCat { time, distance, duration, global, other }