import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../categories.dart';
import '../role_router.dart';
import '../theme.dart';

class RoleSelectionOnboardingScreen extends StatefulWidget {
  const RoleSelectionOnboardingScreen({super.key});

  @override
  State<RoleSelectionOnboardingScreen> createState() => _RoleSelectionOnboardingScreenState();
}

class _RoleSelectionOnboardingScreenState extends State<RoleSelectionOnboardingScreen> {
  String role = 'seeker'; // seeker/provider
  bool loading = false;

  // provider onboarding fields
  final businessCtrl = TextEditingController();
  ServiceCategory category = ServiceCategory.cleaning;

  String? errorText;

  @override
  void dispose() {
    businessCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (loading) return;

    setState(() {
      errorText = null;
      loading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          errorText = "You are not signed in. Please login again.";
          loading = false;
        });
        return;
      }

      if (role == 'provider') {
        if (businessCtrl.text.trim().isEmpty) {
          setState(() {
            errorText = "Business name is required for provider.";
            loading = false;
          });
          return;
        }
      }

      final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);

      final update = <String, dynamic>{
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (role == 'provider') {
        update['businessName'] = businessCtrl.text.trim();
        update['category'] = category.key;
      }

      await doc.set(update, SetOptions(merge: true));

      if (!mounted) return;

      final finalRole = role == 'provider' ? UserRole.provider : UserRole.seeker;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => RoleRouter(role: finalRole)),
            (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => errorText = "Failed to save. Please try again.");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = role == 'provider';

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 18,),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: const [
                  Spacer(),
                  Text("Choose Your Role", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  Spacer(),
                ],
              ),
              const SizedBox(height: 16),

              if (errorText != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEEF0),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFFB91C1C)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          errorText!,
                          style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              _RoleCard(
                title: "Seeker",
                subtitle: "Find and book services around Kuala Lumpur.",
                icon: Icons.search_rounded,
                selected: role == 'seeker',
                onTap: () => setState(() {
                  role = 'seeker';
                  errorText = null;
                }),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                title: "Provider",
                subtitle: "Offer services, manage bookings, and view insights.",
                icon: Icons.storefront_rounded,
                selected: role == 'provider',
                onTap: () => setState(() {
                  role = 'provider';
                  errorText = null;
                }),
              ),

              const SizedBox(height: 16),

              if (isProvider) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: KLPalette.mutedBg,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Provider Onboarding",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 10),

                        const Text("Business Name",
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: businessCtrl,
                          decoration: const InputDecoration(
                            hintText: "e.g., Adam Services",
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),

                        const Text("Main Category",
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<ServiceCategory>(
                          value: category,
                          items: const [
                            DropdownMenuItem(
                              value: ServiceCategory.cleaning,
                              child: Text('Cleaning'),
                            ),
                            DropdownMenuItem(
                              value: ServiceCategory.plumbing,
                              child: Text('Plumbing'),
                            ),
                            DropdownMenuItem(
                              value: ServiceCategory.aircon,
                              child: Text('Air-Conditioning'),
                            ),
                            DropdownMenuItem(
                              value: ServiceCategory.handyman,
                              child: Text('Handyman & Repair'),
                            ),
                            DropdownMenuItem(
                              value: ServiceCategory.tutoring,
                              child: Text('Tutoring & Lessons'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => category = v);
                            }
                          },
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: loading ? null : _save,
                  child: loading
                      ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text("Continue", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: selected ? KLPalette.tint50 : KLPalette.bg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: selected ? KLPalette.primary : KLPalette.border),
        ),
        child: Row(
          children: [
            Container(
              height: 54,
              width: 54,
              decoration: BoxDecoration(
                color: selected ? KLPalette.primary : KLPalette.mutedBg,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: Icon(icon, color: selected ? Colors.white : KLPalette.text),
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
            const Icon(Icons.chevron_right_rounded, color: KLPalette.text2),
          ],
        ),
      ),
    );
  }
}