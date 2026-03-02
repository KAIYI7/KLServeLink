import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/app_snack.dart';

class PaymentMethodScreen extends StatefulWidget {
  const PaymentMethodScreen({super.key});

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  bool loading = true;
  bool saving = false;

  String selected = 'cash'; // default

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final d = doc.data() ?? {};

    final role = (d['role'] ?? '').toString().trim();
    // seeker-only: if not seeker, still show but disable save (optional)
    // Here we just load & allow only if seeker.
    final pm = (d['paymentMethod'] ?? 'cash').toString().trim();
    selected = pm.isEmpty ? 'cash' : pm;

    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => saving = true);

    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await userDoc.get();
      final role = (snap.data()?['role'] ?? '').toString();

      if (role != 'seeker') {
        if (!mounted) return;
        AppSnack.show(
          context,
          "Payment method is for seekers only.",
          type: AppSnackType.info,
        );
        return;
      }

      await userDoc.set({
        'paymentMethod': selected,
        'paymentUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      AppSnack.show(context, "Payment method updated", type: AppSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(context, "Save failed: $e", type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            children: [
              _TopBar(title: "Payment Method", onBack: () => Navigator.pop(context)),
              const SizedBox(height: 18),

              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    decoration: BoxDecoration(
                      color: KLPalette.bg,
                      border: Border.all(color: KLPalette.border),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                      children: [
                        const Text(
                          "Choose how you prefer to pay for services.",
                          style: TextStyle(
                            color: KLPalette.text2,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _PmTile(
                          value: 'cash',
                          groupValue: selected,
                          title: "Cash",
                          subtitle: "Pay after service is completed",
                          icon: Icons.payments_outlined,
                          onChanged: (v) => setState(() => selected = v),
                        ),
                        const SizedBox(height: 12),

                        _PmTile(
                          value: 'card',
                          groupValue: selected,
                          title: "Card",
                          subtitle: "Visa",
                          icon: Icons.credit_card_rounded,
                          onChanged: (v) => setState(() => selected = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: saving
                      ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text("Save", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PmTile extends StatelessWidget {
  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _PmTile({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? KLPalette.tint50 : KLPalette.mutedBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? KLPalette.primary : KLPalette.border),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: KLPalette.tint100,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: Icon(icon, color: KLPalette.primary700),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: (v) {
                if (v == null) return;
                onChanged(v);
              },
              activeColor: KLPalette.primary,
            ),
          ],
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