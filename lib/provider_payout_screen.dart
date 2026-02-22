import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'utils/app_snack.dart';

class ProviderPayoutScreen extends StatefulWidget {
  const ProviderPayoutScreen({super.key});

  @override
  State<ProviderPayoutScreen> createState() => _ProviderPayoutScreenState();
}

class _ProviderPayoutScreenState extends State<ProviderPayoutScreen> {
  final _bankNameCtrl = TextEditingController();
  final _bankAccountNameCtrl = TextEditingController();
  final _bankAccountNumberCtrl = TextEditingController();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadBankDetails();
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _bankAccountNameCtrl.dispose();
    _bankAccountNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBankDetails() async {
    final uid = _uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    setState(() {
      _bankNameCtrl.text = (data['bankName'] ?? '').toString();
      _bankAccountNameCtrl.text = (data['bankAccountName'] ?? '').toString();
      _bankAccountNumberCtrl.text = (data['bankAccountNumber'] ?? '').toString();
    });
  }

  Future<void> _saveBankDetails() async {
    final uid = _uid;
    if (uid == null) return;

    final bankName = _bankNameCtrl.text.trim();
    final bankAccName = _bankAccountNameCtrl.text.trim();
    final bankAccNo = _bankAccountNumberCtrl.text.trim();

    if (bankName.isEmpty || bankAccName.isEmpty || bankAccNo.isEmpty) {
      AppSnack.show(context, 'Please fill in all bank details.', type: AppSnackType.error);
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'bankName': bankName,
          'bankAccountName': bankAccName,
          'bankAccountNumber': bankAccNo,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      AppSnack.show(context, 'Bank details saved.', type: AppSnackType.success);
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(context, 'Failed to save bank details.', type: AppSnackType.error);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _completedBookingsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('providerId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots();
  }

  bool _isCard(String method) {
    final m = method.toLowerCase();
    return m == 'card' || m.contains('card');
  }

  bool _isCaptured(String state) {
    final s = state.toLowerCase();
    return s.contains('captur');
  }

  bool _isPaidOut(String payoutStatus) {
    final p = payoutStatus.toLowerCase();
    return p == 'paid' || p.contains('paid');
  }

  Future<void> _simulatePayout(List<QueryDocumentSnapshot<Map<String, dynamic>>> eligible) async {
    final uid = _uid;
    if (uid == null) return;
    if (eligible.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dCtx) => AlertDialog(
        title: const Text('Payout?'),
        content: Text('This will mark ${eligible.length} booking(s) as paid out.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dCtx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dCtx).pop(true), child: const Text('Mark paid')),
        ],
      ),
    );

    if (ok != true) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final d in eligible) {
        batch.update(d.reference, {
          'payment.payoutStatus': 'paid',
          'payment.payoutAt': FieldValue.serverTimestamp(),
        });
      }

      // Write a payout log
      final payoutRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('payouts')
          .doc();
      batch.set(
        payoutRef,
        {
          'createdAt': FieldValue.serverTimestamp(),
          'bookingIds': eligible.map((e) => e.id).toList(),
          'count': eligible.length,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: false).pop();
      AppSnack.show(context, 'Payout marked as paid.', type: AppSnackType.success);
    } catch (_) {
      if (Navigator.of(context, rootNavigator: false).canPop()) {
        Navigator.of(context, rootNavigator: false).pop();
      }
      AppSnack.show(context, 'Failed to mark payout.', type: AppSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      appBar: AppBar(
        title: const Text('Payout'),
        backgroundColor: KLPalette.bg,
        elevation: 0,
      ),
      body: uid == null
          ? const Center(child: Text('Please login to view payout.'))
          : ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // --- Payout summary ---
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _completedBookingsStream(uid),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              final eligible = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              double total = 0;

              for (final d in docs) {
                final m = d.data();
                final pay = (m['payment'] is Map)
                    ? Map<String, dynamic>.from(m['payment'] as Map)
                    : <String, dynamic>{};

                final method = (pay['method'] ?? m['paymentMethod'] ?? '').toString();
                final state = (pay['state'] ?? '').toString();
                final payoutStatus = (pay['payoutStatus'] ?? m['payoutStatus'] ?? '').toString();

                if (!_isCard(method)) continue;
                if (!_isCaptured(state)) continue;
                if (_isPaidOut(payoutStatus)) continue;

                final amtNum = (pay['amount'] ?? m['totalAmount'] ?? 0);
                final amt = (amtNum is num) ? amtNum.toDouble() : double.tryParse(amtNum.toString()) ?? 0;

                eligible.add(d);
                total += amt;
              }

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KLPalette.mutedBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: KLPalette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 38,
                          width: 38,
                          decoration: BoxDecoration(
                            color: KLPalette.bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: KLPalette.border),
                          ),
                          child: const Icon(Icons.account_balance_wallet_rounded, color: KLPalette.primary),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Eligible payout',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: KLPalette.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      eligible.isEmpty
                          ? 'No captured card payments ready for payout.'
                          : '${eligible.length} booking(s) ready (captured).',
                      style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                    ),
                    if (eligible.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: () => _simulatePayout(eligible),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                          child: const Text('Payout', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tip: Card payments become eligible only after the seeker confirms completion.',
                        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                      ),
                    ]
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 14),

          // --- Bank details ---
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KLPalette.bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: KLPalette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bank details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 6),
                const Text(
                  'Used for payout',
                  style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankNameCtrl,
                  decoration: const InputDecoration(labelText: 'Bank name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankAccountNameCtrl,
                  decoration: const InputDecoration(labelText: 'Account holder name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankAccountNumberCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Account number'),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: KLPalette.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: _saveBankDetails,
                    child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
