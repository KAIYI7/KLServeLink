import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fyp_flutter/pricing/dynamic_pricing_models.dart';
import 'package:fyp_flutter/pricing_rules_validator.dart';
import 'package:fyp_flutter/utils/app_snack.dart';
import 'theme.dart';

class DynamicPricingRulesEditorScreen extends StatefulWidget {
  final List<Map<String, dynamic>> initialRules;
  final Map<String, dynamic>? initialCaps;

  const DynamicPricingRulesEditorScreen({
    super.key,
    required this.initialRules,
    required this.initialCaps,
  });

  @override
  State<DynamicPricingRulesEditorScreen> createState() => _DynamicPricingRulesEditorScreenState();
}

class _DynamicPricingRulesEditorScreenState extends State<DynamicPricingRulesEditorScreen> {
  late List<Map<String, dynamic>> rules;
  Map<String, dynamic>? caps;

  final _maxPercentCtrl = TextEditingController();
  final _maxFixedCtrl = TextEditingController();

  final _maxSurchargePercentCtrl = TextEditingController();
  final _maxDiscountPercentCtrl = TextEditingController();
  final _maxSurchargeFixedCtrl = TextEditingController();
  final _maxDiscountFixedCtrl = TextEditingController();
  final _minTotalCtrl = TextEditingController();
  final _maxTotalCtrl = TextEditingController();

  bool _showAdvancedCaps = false;

  @override
  void initState() {
    super.initState();
    rules = widget.initialRules.map((e) => Map<String, dynamic>.from(e)).toList();
    caps = widget.initialCaps == null ? null : Map<String, dynamic>.from(widget.initialCaps!);

    _maxPercentCtrl.text = (caps?["maxPercent"] ?? "").toString();
    _maxFixedCtrl.text = (caps?["maxFixed"] ?? "").toString();

    _maxSurchargePercentCtrl.text = (caps?["maxSurchargePercent"] ?? "").toString();
    _maxDiscountPercentCtrl.text = (caps?["maxDiscountPercent"] ?? "").toString();
    _maxSurchargeFixedCtrl.text = (caps?["maxSurchargeFixed"] ?? "").toString();
    _maxDiscountFixedCtrl.text = (caps?["maxDiscountFixed"] ?? "").toString();
    _minTotalCtrl.text = (caps?["minTotal"] ?? "").toString();
    _maxTotalCtrl.text = (caps?["maxTotal"] ?? "").toString();

    _showAdvancedCaps = (caps?["maxSurchargePercent"] != null) ||
        (caps?["maxDiscountPercent"] != null) ||
        (caps?["maxSurchargeFixed"] != null) ||
        (caps?["maxDiscountFixed"] != null) ||
        (caps?["minTotal"] != null) ||
        (caps?["maxTotal"] != null);

    _capCtrls = [
      _maxPercentCtrl,
      _maxFixedCtrl,
      _maxSurchargePercentCtrl,
      _maxDiscountPercentCtrl,
      _maxSurchargeFixedCtrl,
      _maxDiscountFixedCtrl,
      _minTotalCtrl,
      _maxTotalCtrl,
    ];
    for (final c in _capCtrls) {
      c.addListener(_onCapsChanged);
    }
  }

  @override
  void dispose() {
    for (final c in _capCtrls) {
      c.removeListener(_onCapsChanged);
    }

    _maxPercentCtrl.dispose();
    _maxFixedCtrl.dispose();
    _maxSurchargePercentCtrl.dispose();
    _maxDiscountPercentCtrl.dispose();
    _maxSurchargeFixedCtrl.dispose();
    _maxDiscountFixedCtrl.dispose();
    _minTotalCtrl.dispose();
    _maxTotalCtrl.dispose();
    super.dispose();
  }

  double? _tryDouble(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  // ---------- Help / Guide UI ----------

  static const String _helpCapsOverview = """
Caps keep your dynamic pricing from becoming too extreme.

How caps are applied:
• Percent / Fixed caps are applied PER RULE (not the final total).
  Example: if two +50% rules match, they can stack (each rule is capped, then both apply).
• Min/Max total caps are applied at the END to clamp the final total.

Defaults (when blank):
• Max percent defaults to 50%
• Max fixed defaults to RM 30
• Min total defaults to RM 0
• Max total defaults to a very high number

Percent rules base:
• Percent changes are calculated using:
  base = floorPrice + packagePrice + (extraHours × hourlyRate)
""";

  static const String _helpMaxPercent = """
Limits each percent-based rule (per rule).

Example:
• Max 50%:
  +80% → +50%
  -60% → -50%

Tip:
• If you want “almost no cap”, set a very high value (e.g., 200 or 500).
""";

  static const String _helpMaxFixed = """
Limits each fixed (RM) rule (per rule).

Example:
• Max RM 30:
  +RM 80 → +RM 30
  -RM 60 → -RM 30

Tip:
• If you want “almost no cap”, set a high value (e.g., 999).
""";

  static const String _helpMaxSurchargePercent = """
Limits percent-based SURCHARGES only (positive % rules).

Example:
• Max surcharge 50%:
  +80% → +50%

If left blank, it falls back to Max percent (or default 50%).
""";

  static const String _helpMaxDiscountPercent = """
Limits percent-based DISCOUNTS only (negative % rules).

Example:
• Max discount 50%:
  -80% → -50%

If left blank, it falls back to Max percent (or default 50%).
""";

  static const String _helpMaxSurchargeFixed = """
Limits fixed SURCHARGES only (positive RM rules).

Example:
• Max surcharge RM 30:
  +RM 80 → +RM 30

If left blank, it falls back to Max fixed (or default RM 30).
""";

  static const String _helpMaxDiscountFixed = """
Limits fixed DISCOUNTS only (negative RM rules).

Example:
• Max discount RM 30:
  -RM 80 → -RM 30

If left blank, it falls back to Max fixed (or default RM 30).
""";

  static const String _helpMinTotal = """
Final total floor (applied after all rules).

Example:
• Min total RM 120:
  If computed total is RM 95 → raised to RM 120

If blank, defaults to RM 0.
""";

  static const String _helpMaxTotal = """
Final total ceiling (applied after all rules).

Example:
• Max total RM 300:
  If computed total is RM 380 → lowered to RM 300

If blank, defaults to “very high” (effectively no ceiling).
""";

  static const String _helpRulesOverview = """
Rules adjust the booking price when their conditions are met.

━━━━━━━━━━━━━━━━━━
HOW RULES WORK
━━━━━━━━━━━━━━━━━━

• Rule Types
  - Fixed (RM): Adds or subtracts a fixed amount.
  - Percent (%): Adds or subtracts a percentage of the calculated base price.

• Conditions
  Rules are evaluated at booking time based on:
  - Day / time
  - Distance
  - Duration (hours)
  - Lead time
  - Date range

• Multiple Rules
  - More than one rule can apply to a booking.
  - If two rules belong to the same "exclusive group",
    only ONE rule from that group will be applied
    (to prevent double discounts or conflicts).
  - Rules from different groups can stack.

━━━━━━━━━━━━━━━━━━
HOW VALIDATION WORKS
━━━━━━━━━━━━━━━━━━

• Save Validation
  The editor checks rules on Save to prevent contradictory
  or ambiguous setups — especially overlapping rules that
  could surprise users (e.g., a surcharge and a discount
  targeting the same time window).

• Exclusive Grouping
  When rules are intended to be alternatives, the system
  automatically assigns exclusive groups so that only one
  can apply at a time.

• Caps
  - Optional caps limit how strong each rule can be.
  - Advanced caps can also clamp the final total price.
""";

  Future<void> _showHelpSheet({required String title, required String body}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
        builder: (_) {
          return SafeArea(
            top: false,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (_, controller) {
                return SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          height: 4,
                          width: 46,
                          decoration: BoxDecoration(
                            color: KLPalette.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        body.trim(),
                        style: const TextStyle(
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }
    );
  }

  Widget _helpIcon({required String title, required String body}) {
    return IconButton(
      tooltip: "What is this?",
      icon: const Icon(Icons.info_outline_rounded, size: 20, color: KLPalette.text2),
      onPressed: () => _showHelpSheet(title: title, body: body),
    );
  }

  late final List<TextEditingController> _capCtrls;

  void _onCapsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _usingAdvancedCapsUI {
    bool has(TextEditingController c) => c.text.trim().isNotEmpty;
    return has(_maxSurchargePercentCtrl) ||
        has(_maxDiscountPercentCtrl) ||
        has(_maxSurchargeFixedCtrl) ||
        has(_maxDiscountFixedCtrl) ||
        has(_minTotalCtrl) ||
        has(_maxTotalCtrl);
  }

  bool get _hasAnyCapsUI {
    bool has(TextEditingController c) => c.text.trim().isNotEmpty;
    return has(_maxPercentCtrl) || has(_maxFixedCtrl) || _usingAdvancedCapsUI;
  }

  bool _isInvalidDouble(TextEditingController c) {
    final t = c.text.trim();
    return t.isNotEmpty && double.tryParse(t) == null;
  }

  void _resetCaps() {
    FocusScope.of(context).unfocus();
    setState(() {
      for (final c in _capCtrls) {
        c.text = "";
      }
      _showAdvancedCaps = false;
    });

    AppSnack.show(context, "Caps reset.", type: AppSnackType.success);
  }

  Widget _capBox({
    required String title,
    required TextEditingController controller,
    required String hint,
    required String helpTitle,
    required String helpBody,
    String? prefixText,
    String? suffixText,
    bool enabled = true,
  }) {
    final err = _isInvalidDouble(controller) ? "Invalid number" : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
            _helpIcon(title: helpTitle, body: helpBody),
          ],
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText,
            suffixText: suffixText,
            isDense: true,
            errorText: err,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
            ),
          ]
        ],
      ),
    );
  }

  Widget _advancedCapsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            "Percent caps",
            subtitle: "Limit percent rules separately for surcharge vs discount",
          ),
          Row(
            children: [
              Expanded(
                child: _capBox(
                  title: "Surcharge (%)",
                  controller: _maxSurchargePercentCtrl,
                  hint: "50",
                  suffixText: "%",
                  helpTitle: "Max surcharge (%)",
                  helpBody: _helpMaxSurchargePercent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _capBox(
                  title: "Discount (%)",
                  controller: _maxDiscountPercentCtrl,
                  hint: "50",
                  suffixText: "%",
                  helpTitle: "Max discount (%)",
                  helpBody: _helpMaxDiscountPercent,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _sectionHeader(
            "Fixed caps",
            subtitle: "Limit fixed RM rules separately for surcharge vs discount",
          ),
          Row(
            children: [
              Expanded(
                child: _capBox(
                  title: "Surcharge (RM)",
                  controller: _maxSurchargeFixedCtrl,
                  hint: "30",
                  prefixText: "RM ",
                  helpTitle: "Max surcharge (RM)",
                  helpBody: _helpMaxSurchargeFixed,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _capBox(
                  title: "Discount (RM)",
                  controller: _maxDiscountFixedCtrl,
                  hint: "30",
                  prefixText: "RM ",
                  helpTitle: "Max discount (RM)",
                  helpBody: _helpMaxDiscountFixed,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _sectionHeader(
            "Total limits",
            subtitle: "Clamp the final total after all rules",
          ),
          Row(
            children: [
              Expanded(
                child: _capBox(
                  title: "Min total (RM)",
                  controller: _minTotalCtrl,
                  hint: "0",
                  prefixText: "RM ",
                  helpTitle: "Min total (RM)",
                  helpBody: _helpMinTotal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _capBox(
                  title: "Max total (RM)",
                  controller: _maxTotalCtrl,
                  hint: "9999",
                  prefixText: "RM ",
                  helpTitle: "Max total (RM)",
                  helpBody: _helpMaxTotal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _capsPreview({required bool usingAdvanced}) {
    // If using advanced caps, legacy maxPercent/maxFixed are NOT saved, so engine falls back to defaults 50/30.
    final legacyPct = usingAdvanced ? 50.0 : (_tryDouble(_maxPercentCtrl.text) ?? 50.0);
    final legacyFix = usingAdvanced ? 30.0 : (_tryDouble(_maxFixedCtrl.text) ?? 30.0);

    final surPct = usingAdvanced ? (_tryDouble(_maxSurchargePercentCtrl.text) ?? legacyPct) : legacyPct;
    final disPct = usingAdvanced ? (_tryDouble(_maxDiscountPercentCtrl.text) ?? legacyPct) : legacyPct;

    final surFix = usingAdvanced ? (_tryDouble(_maxSurchargeFixedCtrl.text) ?? legacyFix) : legacyFix;
    final disFix = usingAdvanced ? (_tryDouble(_maxDiscountFixedCtrl.text) ?? legacyFix) : legacyFix;

    final minTotal = usingAdvanced ? (_tryDouble(_minTotalCtrl.text) ?? 0.0) : 0.0;
    final maxTotal = usingAdvanced ? (_tryDouble(_maxTotalCtrl.text) ?? 1e12) : 1e12;

    double clampTotal(double v) => v.clamp(minTotal, maxTotal).toDouble();

    String rm(double v) => "RM ${v.toStringAsFixed(0)}";
    String pct(double v) => "${v.toStringAsFixed(0)}%";

    final pPlus = math.min(80.0, surPct);
    final pMinus = math.min(80.0, disPct);
    final fPlus = math.min(80.0, surFix);
    final fMinus = math.min(80.0, disFix);

    final hiRaw = 380.0;
    final loRaw = 95.0;

    final hiClamped = clampTotal(hiRaw);
    final loClamped = clampTotal(loRaw);

    String maxTotalLabel() {
      if (!usingAdvanced || maxTotal >= 1e11) return "No max";
      return rm(maxTotal);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KLPalette.mutedBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KLPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            usingAdvanced ? "Mode: Advanced" : "Mode: Basic",
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),

          const Text("Percent rule example", style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text("+80% → +${pct(pPlus)}", style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
          Text("-80% → -${pct(pMinus)}", style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),

          const SizedBox(height: 10),

          const Text("Fixed rule example", style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text("+RM 80 → +${rm(fPlus)}", style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
          Text("-RM 80 → -${rm(fMinus)}", style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),

          const SizedBox(height: 10),

          const Text("Total clamp example", style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            "${rm(loRaw)} → ${rm(loClamped)}  (min: ${rm(minTotal)})",
            style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
          ),
          Text(
            "${rm(hiRaw)} → ${rm(hiClamped)}  (max: ${maxTotalLabel()})",
            style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
          ),

          if (usingAdvanced) ...[
            const SizedBox(height: 10),
            const Text(
              "Note: In Advanced mode, Basic caps are ignored when saving.\nIf an advanced field is left blank, defaults are used (50% / RM30).",
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.25),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addOrEdit({Map<String, dynamic>? initial, int? index}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _RuleEditorSheet(initial: initial),
    );

    if (result == null) return;

    setState(() {
      if (index == null) {
        rules.add(result);
      } else {
        rules[index] = result;
      }
    });
  }

  Future<void> _saveAndPop() async {
    final anyAdvanced = _usingAdvancedCapsUI;

    final invalid = <String>[];

    void checkNumber(TextEditingController c, String name) {
      final t = c.text.trim();
      if (t.isNotEmpty && double.tryParse(t) == null) invalid.add(name);
    }

    if (anyAdvanced) {
      checkNumber(_maxSurchargePercentCtrl, "Max surcharge (%)");
      checkNumber(_maxDiscountPercentCtrl, "Max discount (%)");
      checkNumber(_maxSurchargeFixedCtrl, "Max surcharge (RM)");
      checkNumber(_maxDiscountFixedCtrl, "Max discount (RM)");
      checkNumber(_minTotalCtrl, "Min total");
      checkNumber(_maxTotalCtrl, "Max total");
    } else {
      checkNumber(_maxPercentCtrl, "Max percent");
      checkNumber(_maxFixedCtrl, "Max fixed");
    }

    if (invalid.isNotEmpty) {
      AppSnack.show(
        context,
        "Please enter valid numbers for: ${invalid.join(', ')}",
        type: AppSnackType.error,
      );
      return;
    }

    // Parse values
    final maxPercent = _tryDouble(_maxPercentCtrl.text);
    final maxFixed = _tryDouble(_maxFixedCtrl.text);

    final maxSurchargePercent = _tryDouble(_maxSurchargePercentCtrl.text);
    final maxDiscountPercent = _tryDouble(_maxDiscountPercentCtrl.text);
    final maxSurchargeFixed = _tryDouble(_maxSurchargeFixedCtrl.text);
    final maxDiscountFixed = _tryDouble(_maxDiscountFixedCtrl.text);
    final minTotal = _tryDouble(_minTotalCtrl.text);
    final maxTotal = _tryDouble(_maxTotalCtrl.text);

    // Non-negative caps
    bool nonNeg(double? v) => v == null || v >= 0;

    if (anyAdvanced) {
      final bad = <String>[];
      if (!nonNeg(maxSurchargePercent)) bad.add("Max surcharge (%)");
      if (!nonNeg(maxDiscountPercent)) bad.add("Max discount (%)");
      if (!nonNeg(maxSurchargeFixed)) bad.add("Max surcharge (RM)");
      if (!nonNeg(maxDiscountFixed)) bad.add("Max discount (RM)");
      if (!nonNeg(minTotal)) bad.add("Min total");
      if (!nonNeg(maxTotal)) bad.add("Max total");

      if (bad.isNotEmpty) {
        AppSnack.show(
          context,
          "These must be ≥ 0: ${bad.join(', ')}",
          type: AppSnackType.error,
        );
        return;
      }

      if (minTotal != null && maxTotal != null && minTotal > maxTotal) {
        AppSnack.show(
          context,
          "Min total cannot be greater than Max total.",
          type: AppSnackType.error,
        );
        return;
      }
    } else {
      final bad = <String>[];
      if (!nonNeg(maxPercent)) bad.add("Max percent");
      if (!nonNeg(maxFixed)) bad.add("Max fixed");

      if (bad.isNotEmpty) {
        AppSnack.show(
          context,
          "These must be ≥ 0: ${bad.join(', ')}",
          type: AppSnackType.error,
        );
        return;
      }
    }

    final outCaps = <String, dynamic>{};

    if (anyAdvanced) {
      if (maxSurchargePercent != null) outCaps["maxSurchargePercent"] = maxSurchargePercent;
      if (maxDiscountPercent != null) outCaps["maxDiscountPercent"] = maxDiscountPercent;
      if (maxSurchargeFixed != null) outCaps["maxSurchargeFixed"] = maxSurchargeFixed;
      if (maxDiscountFixed != null) outCaps["maxDiscountFixed"] = maxDiscountFixed;
      if (minTotal != null) outCaps["minTotal"] = minTotal;
      if (maxTotal != null) outCaps["maxTotal"] = maxTotal;
    } else {
      if (maxPercent != null) outCaps["maxPercent"] = maxPercent;
      if (maxFixed != null) outCaps["maxFixed"] = maxFixed;
    }

    final capsFinal = outCaps.isEmpty ? null : outCaps;

    final withGroups = PricingRulesValidator.autoAssignExclusiveGroups(rules);
    final errs = PricingRulesValidator.validate(withGroups);

    if (errs.isNotEmpty) {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text("Invalid pricing rules"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: errs.map((e) => Text("• $e")).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      PricingEditorResult(
        rules: withGroups,
        caps: capsFinal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usingAdvanced = _usingAdvancedCapsUI;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            children: [
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
                  const Text("Dynamic Pricing", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 14),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    _card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text("Caps (optional)", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                                const SizedBox(width: 2),
                                _helpIcon(title: "How caps work", body: _helpCapsOverview),
                                const Spacer(),
                                SizedBox(
                                  height: 34,
                                  child: FilledButton.tonal(
                                    onPressed: _hasAnyCapsUI ? _resetCaps : null,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.restart_alt_rounded, size: 18),
                                        SizedBox(width: 6),
                                        Text("Reset"),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "Caps limit how strong each rule can be. Total caps clamp the final price.",
                              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),

                            Row(
                              children: [
                                const Text("Basic caps", style: TextStyle(fontWeight: FontWeight.w900)),
                                const Spacer(),
                                if (usingAdvanced)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: KLPalette.mutedBg,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: KLPalette.border),
                                    ),
                                    child: const Text(
                                      "Disabled",
                                      style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            AbsorbPointer(
                              absorbing: usingAdvanced,
                              child: Opacity(
                                opacity: usingAdvanced ? 0.45 : 1,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _capBox(
                                        title: "Max percent (%)",
                                        controller: _maxPercentCtrl,
                                        hint: "50",
                                        suffixText: "%",
                                        enabled: !usingAdvanced,
                                        helpTitle: "Max percent (%)",
                                        helpBody: _helpMaxPercent,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _capBox(
                                        title: "Max fixed (RM)",
                                        controller: _maxFixedCtrl,
                                        hint: "30",
                                        prefixText: "RM ",
                                        enabled: !usingAdvanced,
                                        helpTitle: "Max fixed (RM)",
                                        helpBody: _helpMaxFixed,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            if (usingAdvanced) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: KLPalette.mutedBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: KLPalette.border),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 18, color: KLPalette.text2),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Advanced caps are active — Basic caps will be ignored when saving.",
                                        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 10),

                            Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                key: ValueKey(usingAdvanced),
                                initiallyExpanded: _showAdvancedCaps || usingAdvanced,
                                onExpansionChanged: (v) => setState(() => _showAdvancedCaps = v),
                                title: Row(
                                  children: [
                                    const Text("Advanced caps", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                                    const SizedBox(width: 8),
                                    if (usingAdvanced)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: KLPalette.primary.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: KLPalette.border),
                                        ),
                                        child: const Text(
                                          "Active",
                                          style: TextStyle(color: KLPalette.primary, fontWeight: FontWeight.w900, fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: const Text(
                                  "Separate surcharge vs discount, plus min/max total",
                                  style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                                ),
                                childrenPadding: const EdgeInsets.only(top: 10, bottom: 6),
                                children: [
                                  _advancedCapsSection(),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                const Text("Preview (how caps clamp)", style: TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(width: 6),
                                _helpIcon(
                                  title: "Preview",
                                  body: "This is a quick example of how your caps will clamp a large rule.\nIt’s only a guide and doesn’t change your pricing.",
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _capsPreview(usingAdvanced: usingAdvanced),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        const Text("Rules", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(width: 2),
                        _helpIcon(
                          title: "Pricing rules & validation",
                          body: _helpRulesOverview,
                        ),
                        const Spacer(),
                        FilledButton.tonal(
                          onPressed: () => _addOrEdit(),
                          child: const Text("Add Rule"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (rules.isEmpty)
                      _card(
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: Text(
                              "No pricing rules yet.\nTap “Add Rule” to create one.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.3),
                            ),
                          ),
                        ),
                      )
                    else
                      ...List.generate(rules.length, (i) {
                        final r = rules[i];
                        final label = (r["label"] ?? r["id"] ?? "Rule").toString();
                        final when = (r["when"] is Map) ? (r["when"] as Map).cast<String, dynamic>() : <String, dynamic>{};
                        final desc = _describeWhen(when);

                        final effect = _describeEffect(r);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _card(
                            child: InkWell(
                              onTap: () => _addOrEdit(initial: r, index: i),
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.local_offer_rounded, color: KLPalette.primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                                          const SizedBox(height: 4),
                                          Text(desc, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 6),
                                          Text(effect, style: const TextStyle(fontWeight: FontWeight.w900)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    InkWell(
                                      onTap: () {
                                        setState(() => rules.removeAt(i));
                                      },
                                      borderRadius: BorderRadius.circular(999),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.delete_outline_rounded, color: KLPalette.text2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
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
          child: SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: KLPalette.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: _saveAndPop,
              child: const Text("Save", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _card({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: KLPalette.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: child,
      ),
    );
  }

  static String _describeWhen(Map<String, dynamic> when) {
    final parts = <String>[];

    final days = (when["days"] as List?)?.cast<dynamic>().map((e) => (e as num).toInt()).toList();
    if (days != null && days.isNotEmpty) {
      parts.add("Days: ${days.join(', ')}");
    }

    final sh = (when["startHour"] as num?)?.toInt();
    final eh = (when["endHour"] as num?)?.toInt();
    if (sh != null && eh != null) {
      parts.add("Time: ${sh.toString().padLeft(2,'0')}:00–${eh.toString().padLeft(2,'0')}:59");
    }

    final minD = (when["minDistanceKm"] as num?)?.toDouble();
    final maxD = (when["maxDistanceKm"] as num?)?.toDouble();
    if (minD != null || maxD != null) {
      if (minD != null && maxD != null) parts.add("Distance ${minD.toStringAsFixed(0)}–${maxD.toStringAsFixed(0)} km");
      else if (minD != null) parts.add("Distance ≥ ${minD.toStringAsFixed(0)} km");
      else parts.add("Distance ≤ ${maxD!.toStringAsFixed(0)} km");
    }

    final minH = (when["minHours"] as num?)?.toInt();
    final maxH = (when["maxHours"] as num?)?.toInt();
    if (minH != null || maxH != null) {
      if (minH != null && maxH != null) parts.add("Hours $minH–$maxH");
      else if (minH != null) parts.add("Hours ≥ $minH");
      else parts.add("Hours ≤ $maxH");
    }

    final minLead = (when["minLeadHours"] as num?)?.toInt();
    if (minLead != null) parts.add("Lead ≥ $minLead h");

    final sd = (when["startDate"] ?? "").toString().trim();
    final ed = (when["endDate"] ?? "").toString().trim();
    if (sd.isNotEmpty || ed.isNotEmpty) {
      if (sd.isNotEmpty && ed.isNotEmpty) parts.add("Dates $sd → $ed");
      else if (sd.isNotEmpty) parts.add("From $sd");
      else parts.add("Until $ed");
    }

    return parts.isEmpty ? "Always applies" : parts.join(" • ");
  }

  static String _describeEffect(Map<String, dynamic> r) {
    final type = (r["type"] ?? "fixed").toString(); // "fixed" | "percent"
    final value = (r["value"] is num) ? (r["value"] as num).toDouble() : 0.0;

    final prefix = value >= 0 ? "+" : "-";
    final absV = value.abs();

    if (type == "percent") return "$prefix${absV.toStringAsFixed(0)}%";
    return "$prefix RM ${absV.toStringAsFixed(2)}";
  }
}

class _RuleEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _RuleEditorSheet({this.initial});

  @override
  State<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<_RuleEditorSheet> {
  final _labelCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _minDistanceCtrl = TextEditingController();

  bool _discount = false; // false=surcharge, true=discount
  String _mode = "fixed"; // fixed | percent

  final Set<int> _days = {}; // 1..7
  int? _startHour;
  int? _endHour;
  double? _minDistanceKm;

  String _trigger = "time"; // time | distance | duration | lead | daterange | custom

  // Distance
  final _maxDistanceCtrl = TextEditingController();
  double? _maxDistanceKm;

  // Duration
  final _minHoursCtrl = TextEditingController();
  final _maxHoursCtrl = TextEditingController();
  int? _minHours;
  int? _maxHours;

  // Lead time
  final _minLeadHoursCtrl = TextEditingController();
  int? _minLeadHours;

  // Date range (YYYY-MM-DD)
  final _startDateCtrl = TextEditingController();
  final _endDateCtrl = TextEditingController();
  String? _startDate;
  String? _endDate;


  @override
  void initState() {
    super.initState();
    final r = widget.initial;

    if (r != null) {
      _labelCtrl.text = (r["label"] ?? "").toString();
      _mode = (r["type"] ?? "fixed").toString();

      final v = r["value"];
      final dv = (v is num) ? v.toDouble() : 0.0;
      _discount = dv < 0;
      _valueCtrl.text = dv.abs().toString();

      final when = (r["when"] is Map) ? (r["when"] as Map).cast<String, dynamic>() : <String, dynamic>{};
      _trigger = _inferTrigger(when);

      final days = (when["days"] as List?)?.cast<dynamic>().map((e) => (e as num).toInt()).toList() ?? [];
      _days.addAll(days);

      _startHour = (when["startHour"] as num?)?.toInt();
      _endHour = (when["endHour"] as num?)?.toInt();

      // Distance
      _minDistanceKm = (when["minDistanceKm"] as num?)?.toDouble();
      _minDistanceCtrl.text = (_minDistanceKm == null) ? "" : _minDistanceKm.toString();
      _maxDistanceKm = (when["maxDistanceKm"] as num?)?.toDouble();
      _maxDistanceCtrl.text = (_maxDistanceKm == null) ? "" : _maxDistanceKm.toString();

      // Duration
      _minHours = (when["minHours"] as num?)?.toInt();
      _maxHours = (when["maxHours"] as num?)?.toInt();
      _minHoursCtrl.text = (_minHours == null) ? "" : _minHours.toString();
      _maxHoursCtrl.text = (_maxHours == null) ? "" : _maxHours.toString();

      // Lead time
      _minLeadHours = (when["minLeadHours"] as num?)?.toInt();
      _minLeadHoursCtrl.text = (_minLeadHours == null) ? "" : _minLeadHours.toString();

      // Date range
      _startDate = (when["startDate"] ?? "").toString().trim();
      _endDate = (when["endDate"] ?? "").toString().trim();
      _startDate = _startDate!.isEmpty ? null : _startDate;
      _endDate = _endDate!.isEmpty ? null : _endDate;
      _startDateCtrl.text = _startDate ?? "";
      _endDateCtrl.text = _endDate ?? "";
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _valueCtrl.dispose();
    _minDistanceCtrl.dispose();
    _maxDistanceCtrl.dispose();
    _minHoursCtrl.dispose();
    _maxHoursCtrl.dispose();
    _minLeadHoursCtrl.dispose();
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelCtrl.text.trim();
    final value = double.tryParse(_valueCtrl.text.trim()) ?? 0;

    final when = <String, dynamic>{};

    final isCustom = _trigger == "custom";

    // Time
    if (isCustom || _trigger == "time") {
      if (_days.isNotEmpty) when["days"] = _days.toList()..sort();
      if (_startHour != null && _endHour != null) {
        when["startHour"] = _startHour;
        when["endHour"] = _endHour;
      }
    }

    // Distance
    if (isCustom || _trigger == "distance") {
      if (_minDistanceKm != null) when["minDistanceKm"] = _minDistanceKm;
      if (_maxDistanceKm != null) when["maxDistanceKm"] = _maxDistanceKm;
    }

    // Duration
    if (isCustom || _trigger == "duration") {
      if (_minHours != null) when["minHours"] = _minHours;
      if (_maxHours != null) when["maxHours"] = _maxHours;
    }

    // Lead time
    if (isCustom || _trigger == "lead") {
      if (_minLeadHours != null) when["minLeadHours"] = _minLeadHours;
    }

    // Date range
    if (isCustom || _trigger == "daterange") {
      if (_startDate != null && _startDate!.isNotEmpty) when["startDate"] = _startDate;
      if (_endDate != null && _endDate!.isNotEmpty) when["endDate"] = _endDate;
    }

    final out = <String, dynamic>{
      "id": (widget.initial?["id"] ?? DateTime.now().millisecondsSinceEpoch.toString()),
      "label": label.isEmpty ? "Rule" : label,
      "type": _mode, // "fixed" | "percent"
      "value": _discount ? -value : value, // negative = discount
      "when": when,
    };

    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
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
              child: Text("Edit Rule", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(labelText: "Label", hintText: "e.g., Weekend surcharge"),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _mode,
                    items: const [
                      DropdownMenuItem(value: "fixed", child: Text("Fixed (RM)")),
                      DropdownMenuItem(value: "percent", child: Text("Percent (%)")),
                    ],
                    onChanged: (v) => setState(() => _mode = v ?? "fixed"),
                    decoration: const InputDecoration(labelText: "Mode"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<bool>(
                    value: _discount,
                    items: const [
                      DropdownMenuItem(value: false, child: Text("Surcharge (+)")),
                      DropdownMenuItem(value: true, child: Text("Discount (-)")),
                    ],
                    onChanged: (v) => setState(() => _discount = v ?? false),
                    decoration: const InputDecoration(labelText: "Effect"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _valueCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Value",
                hintText: _mode == "percent" ? "e.g., 10" : "e.g., 15",
              ),
            ),

            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              value: _trigger,
              items: const [
                DropdownMenuItem(value: "time", child: Text("Time window (days & hours)")),
                DropdownMenuItem(value: "distance", child: Text("Distance-based")),
                DropdownMenuItem(value: "duration", child: Text("Duration-based")),
                DropdownMenuItem(value: "lead", child: Text("Lead time (last-minute)")),
                DropdownMenuItem(value: "daterange", child: Text("Date range (promo period)")),
                DropdownMenuItem(value: "custom", child: Text("Custom (advanced)")),
              ],
              onChanged: (v) => _setTrigger(v ?? "time"),
              decoration: const InputDecoration(labelText: "Rule type"),
            ),

            const SizedBox(height: 14),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Conditions (when)", style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 10),

            if (_trigger == "time" || _trigger == "custom") ...[
              _DaysPicker(
                initial: _days,
                onChanged: (s) => setState(() {
                  _days
                    ..clear()
                    ..addAll(s);
                }),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _startHour,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text("Start hour")),
                        ...List.generate(24, (i) => DropdownMenuItem(value: i, child: Text("${i.toString().padLeft(2,'0')}:00"))),
                      ],
                      onChanged: (v) => setState(() => _startHour = v),
                      decoration: const InputDecoration(labelText: "Start hour"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _endHour,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text("End hour")),
                        ...List.generate(24, (i) => DropdownMenuItem(value: i, child: Text("${i.toString().padLeft(2,'0')}:00"))),
                      ],
                      onChanged: (v) => setState(() => _endHour = v),
                      decoration: const InputDecoration(labelText: "End hour"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_trigger == "distance" || _trigger == "custom") ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Min distance (km)", hintText: "e.g., 5"),
                      onChanged: (t) => setState(() => _minDistanceKm = double.tryParse(t.trim())),
                      controller: _minDistanceCtrl,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Max distance (km)", hintText: "e.g., 20"),
                      onChanged: (t) => setState(() => _maxDistanceKm = double.tryParse(t.trim())),
                      controller: _maxDistanceCtrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_trigger == "duration" || _trigger == "custom") ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minHoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Min hours",
                        hintText: "e.g., 2",
                      ),
                      onChanged: (t) => setState(() => _minHours = int.tryParse(t.trim())),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxHoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Max hours",
                        hintText: "e.g., 6",
                      ),
                      onChanged: (t) => setState(() => _maxHours = int.tryParse(t.trim())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_trigger == "lead" || _trigger == "custom") ...[
              TextField(
                controller: _minLeadHoursCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Minimum lead time (hours)",
                  hintText: "e.g., 24",
                ),
                onChanged: (t) => setState(() => _minLeadHours = int.tryParse(t.trim())),
              ),
              const SizedBox(height: 12),
            ],

            if (_trigger == "daterange" || _trigger == "custom") ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startDateCtrl,
                      decoration: const InputDecoration(
                        labelText: "Start date (YYYY-MM-DD)",
                        hintText: "2026-02-01",
                      ),
                      onChanged: (t) => setState(() => _startDate = t.trim().isEmpty ? null : t.trim()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endDateCtrl,
                      decoration: const InputDecoration(
                        labelText: "End date (YYYY-MM-DD)",
                        hintText: "2026-02-28",
                      ),
                      onChanged: (t) => setState(() => _endDate = t.trim().isEmpty ? null : t.trim()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 6),

            SizedBox(
              height: 52,
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: KLPalette.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: _save,
                child: const Text("Save rule", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _inferTrigger(Map<String, dynamic> when) {
    bool hasTime = when.containsKey("days") || when.containsKey("startHour") || when.containsKey("endHour");
    bool hasDistance = when.containsKey("minDistanceKm") || when.containsKey("maxDistanceKm");
    bool hasDuration = when.containsKey("minHours") || when.containsKey("maxHours");
    bool hasLead = when.containsKey("minLeadHours");
    bool hasDate = when.containsKey("startDate") || when.containsKey("endDate");

    final groups = [hasTime, hasDistance, hasDuration, hasLead, hasDate].where((x) => x).length;
    if (groups > 1) return "custom";

    if (hasLead) return "lead";
    if (hasDate) return "daterange";
    if (hasDuration) return "duration";
    if (hasDistance) return "distance";
    if (hasTime) return "time";
    return "custom";
  }

  void _clearTime() {
    _days.clear();
    _startHour = null;
    _endHour = null;
  }

  void _clearDistance() {
    _minDistanceKm = null;
    _maxDistanceKm = null;
    _minDistanceCtrl.text = "";
    _maxDistanceCtrl.text = "";
  }

  void _clearDuration() {
    _minHours = null;
    _maxHours = null;
    _minHoursCtrl.text = "";
    _maxHoursCtrl.text = "";
  }

  void _clearLead() {
    _minLeadHours = null;
    _minLeadHoursCtrl.text = "";
  }

  void _clearDateRange() {
    _startDate = null;
    _endDate = null;
    _startDateCtrl.text = "";
    _endDateCtrl.text = "";
  }

  void _setTrigger(String next) {
    if (next == _trigger) return;

    setState(() {
      // If switching into custom, keep everything (advanced mode)
      if (next == "custom") {
        _trigger = next;
        return;
      }

      // clear fields that are not part of the selected trigger
      switch (next) {
        case "time":
          _clearDistance();
          _clearDuration();
          _clearLead();
          _clearDateRange();
          break;
        case "distance":
          _clearTime();
          _clearDuration();
          _clearLead();
          _clearDateRange();
          break;
        case "duration":
          _clearTime();
          _clearDistance();
          _clearLead();
          _clearDateRange();
          break;
        case "lead":
          _clearTime();
          _clearDistance();
          _clearDuration();
          _clearDateRange();
          break;
        case "daterange":
          _clearTime();
          _clearDistance();
          _clearDuration();
          _clearLead();
          break;
      }

      _trigger = next;
    });
  }

}

class _DaysPicker extends StatefulWidget {
  final Set<int> initial;
  final ValueChanged<Set<int>> onChanged;
  const _DaysPicker({required this.initial, required this.onChanged});

  @override
  State<_DaysPicker> createState() => _DaysPickerState();
}

class _DaysPickerState extends State<_DaysPicker> {
  late Set<int> days;

  @override
  void initState() {
    super.initState();
    days = {...widget.initial};
  }

  void _toggle(int d) {
    setState(() {
      if (days.contains(d)) days.remove(d);
      else days.add(d);
    });
    widget.onChanged(days);
  }

  @override
  Widget build(BuildContext context) {
    const labels = {
      1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun",
    };

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: labels.entries.map((e) {
        final selected = days.contains(e.key);
        return InkWell(
          onTap: () => _toggle(e.key),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? KLPalette.primary : KLPalette.bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: KLPalette.border),
            ),
            child: Text(
              e.value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : KLPalette.text,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
