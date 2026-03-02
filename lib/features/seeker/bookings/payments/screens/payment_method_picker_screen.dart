import 'package:flutter/material.dart';
import '../../../../../core/theme/theme.dart';
import '../data/payment_method_model.dart';

class PaymentMethodPickerScreen extends StatefulWidget {
  final PaymentMethodUi initial;
  const PaymentMethodPickerScreen({super.key, required this.initial});

  @override
  State<PaymentMethodPickerScreen> createState() => _PaymentMethodPickerScreenState();
}

class _PaymentMethodPickerScreenState extends State<PaymentMethodPickerScreen> {
  late PaymentMethodUi selected;

  @override
  void initState() {
    super.initState();
    selected = widget.initial;
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
              _TopBar(title: "Payment Method", onBack: () => Navigator.pop(context)),
              const SizedBox(height: 18),

              Expanded(
                child: ListView.separated(
                  itemCount: PaymentMethodUi.all.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final m = PaymentMethodUi.all[i];
                    final isSelected = m.id == selected.id;

                    return InkWell(
                      onTap: () => setState(() => selected = m),
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
                              child: Icon(m.icon, color: KLPalette.text),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(m.subtitle, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
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
                  onPressed: () => Navigator.pop(context, selected),
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