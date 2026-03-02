import 'package:flutter/material.dart';

enum PaymentMethodType { card, cash }

class PaymentMethodUi {
  final String id;
  final PaymentMethodType type;
  final String title;
  final String subtitle;
  final IconData icon;

  const PaymentMethodUi({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  String get label => title;

  static PaymentMethodUi fromId(String id) => byId(id);

  static const card = PaymentMethodUi(
    id: "card",
    type: PaymentMethodType.card,
    title: "Card",
    subtitle: "Authorize deposit • Pay after confirmation",
    icon: Icons.credit_card_rounded,
  );

  static const cash = PaymentMethodUi(
    id: "cash",
    type: PaymentMethodType.cash,
    title: "Cash",
    subtitle: "Pay on-site • Provider confirms received",
    icon: Icons.payments_rounded,
  );

  static const all = <PaymentMethodUi>[card, cash];

  static PaymentMethodUi byId(String id) {
    final x = id.trim().toLowerCase();
    return all.firstWhere((e) => e.id == x, orElse: () => cash);
  }
}