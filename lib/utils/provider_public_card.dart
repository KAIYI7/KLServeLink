import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

class ProviderPublicCard extends StatelessWidget {
  final String providerId;
  final VoidCallback? onTap;

  const ProviderPublicCard({
    super.key,
    required this.providerId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (providerId.trim().isEmpty) {
      return _shell(
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            "Provider info unavailable",
            style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    final ref = FirebaseFirestore.instance.collection('users').doc(providerId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(radius: 22, backgroundColor: KLPalette.mutedBg),
                  SizedBox(width: 12),
                  Expanded(child: Text("Loading provider...", style: TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2))),
                ],
              ),
            ),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                "Provider info unavailable",
                style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w800),
              ),
            ),
          );
        }

        final data = snap.data!.data() ?? {};
        final provider = (data['provider'] as Map?)?.cast<String, dynamic>() ?? {};

        final name = (data['name'] ?? '').toString().trim();
        final email = (data['email'] ?? '').toString().trim();
        final businessName = (provider['businessName'] ?? '').toString().trim();
        final category = (provider['category'] ?? '').toString().trim();

        final businessAddress = (data['businessAddress'] ?? '').toString().trim();

        final title = businessName.isNotEmpty ? businessName : (name.isNotEmpty ? name : "Provider");
        final subtitle = category.isNotEmpty ? category : (email.isNotEmpty ? email : "Service Provider");

        return _shell(
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: KLPalette.tint50,
                    child: Icon(Icons.storefront_rounded, color: KLPalette.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                        ),
                        if (businessAddress.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.place_outlined, size: 16, color: KLPalette.text2),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  businessAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: KLPalette.text2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: KLPalette.bg,
          border: Border.all(color: KLPalette.border),
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      ),
    );
  }
}