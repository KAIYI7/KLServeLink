import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/theme/theme.dart';

class CardPaymentFormScreen extends StatefulWidget {
  final double amount;
  const CardPaymentFormScreen({super.key, required this.amount});

  @override
  State<CardPaymentFormScreen> createState() => _CardPaymentFormScreenState();
}

class _CardPaymentFormScreenState extends State<CardPaymentFormScreen> {
  final _cardCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _expCtrl = TextEditingController(); // MM/YY
  final _cvvCtrl = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _cardCtrl.dispose();
    _nameCtrl.dispose();
    _expCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  String _digits(String s) => s.replaceAll(RegExp(r"\D"), "");

  bool _luhnValid(String input) {
    final digits = _digits(input);
    if (digits.length < 13 || digits.length > 19) return false;

    var sum = 0;
    var alt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = int.parse(digits[i]);
      if (alt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alt = !alt;
    }
    return sum % 10 == 0;
  }

  String _brand(String digits) {
    if (digits.startsWith("4")) return "VISA";
    if (digits.startsWith("5")) return "MASTERCARD";
    if (digits.startsWith("34") || digits.startsWith("37")) return "AMEX";
    return "CARD";
  }

  bool _expValid(String s) {
    final t = s.trim();
    final m = RegExp(r"^\d{2}/\d{2}$").hasMatch(t);
    if (!m) return false;

    final mm = int.tryParse(t.substring(0, 2));
    final yy = int.tryParse(t.substring(3, 5));
    if (mm == null || yy == null) return false;
    if (mm < 1 || mm > 12) return false;

    final now = DateTime.now();
    final year = 2000 + yy;
    final lastDay = DateTime(year, mm + 1, 0);
    return lastDay.isAfter(DateTime(now.year, now.month, now.day));
  }

  Future<void> _authorize() async {
    final digits = _digits(_cardCtrl.text);
    final name = _nameCtrl.text.trim();
    final exp = _expCtrl.text.trim();
    final cvv = _digits(_cvvCtrl.text);

    final errors = <String>[];
    if (!_luhnValid(digits)) errors.add("Card number is invalid");
    if (name.isEmpty) errors.add("Cardholder name is required");
    if (!_expValid(exp)) errors.add("Expiry must be valid (MM/YY)");
    if (cvv.length < 3 || cvv.length > 4) errors.add("CVV must be 3–4 digits");

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errors.first)),
      );
      return;
    }

    setState(() => _busy = true);
    FocusScope.of(context).unfocus();

    // Simulate “bank authorization”
    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;
    setState(() => _busy = false);

    Navigator.pop(context, {
      "cardBrand": _brand(digits),
      "cardLast4": digits.substring(digits.length - 4),
      "cardHolder": name,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: _busy ? null : () => Navigator.pop(context),
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
                  const Text("Card Payment", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 14),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KLPalette.mutedBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: KLPalette.border),
                ),
                child: Text(
                      "Amount authorized (deposit): RM ${widget.amount.toStringAsFixed(2)}",
                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.25),
                ),
              ),

              const SizedBox(height: 14),

              Expanded(
                child: ListView(
                  children: [
                    TextField(
                      controller: _cardCtrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[0-9 ]")),
                        LengthLimitingTextInputFormatter(23),
                      ],
                      decoration: const InputDecoration(
                        labelText: "Card number",
                        hintText: "e.g. 4242 4242 4242 4242",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameCtrl,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: "Cardholder name",
                        hintText: "e.g. Derrick Chua",
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _expCtrl,
                            enabled: !_busy,
                            keyboardType: TextInputType.datetime,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r"[0-9/]")),
                              LengthLimitingTextInputFormatter(5),
                            ],
                            decoration: const InputDecoration(
                              labelText: "Expiry (MM/YY)",
                              hintText: "02/30",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _cvvCtrl,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            decoration: const InputDecoration(
                              labelText: "CVV",
                              hintText: "123",
                            ),
                            obscureText: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KLPalette.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: _busy ? null : _authorize,
                  child: _busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                    "Authorize RM ${widget.amount.toStringAsFixed(2)}",
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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