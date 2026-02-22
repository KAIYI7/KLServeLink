import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'theme.dart';
import 'utils/app_snack.dart';

import 'user_profile_repo.dart';
import 'profile_photo_service.dart';
import 'photo_picker_sheet.dart';
import 'provider_business_address_screen.dart';

class ProviderEditProfileScreen extends StatefulWidget {
  const ProviderEditProfileScreen({super.key});

  @override
  State<ProviderEditProfileScreen> createState() => _ProviderEditProfileScreenState();
}

class _ProviderEditProfileScreenState extends State<ProviderEditProfileScreen> {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();

  bool loading = true;

  final _repo = UserProfileRepo();
  final _photo = ProfilePhotoService();
  final _picker = ImagePicker();

  String photoUrl = '';

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
    final d = doc.data() ?? <String, dynamic>{};

    photoUrl = (d['photoUrl'] ?? '').toString().trim();
    nameCtrl.text = (d['name'] ?? '').toString();
    phoneCtrl.text = (d['phone'] ?? '').toString();
    addressCtrl.text = (d['businessAddress'] ?? d['address'] ?? '').toString();

    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '-';

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [KLPalette.tint50, KLPalette.bg],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              children: [
                _TopBar(title: "Edit Profile", onBack: () => Navigator.pop(context)),
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
                          const SizedBox(height: 6),
                          Center(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  height: 84,
                                  width: 84,
                                  decoration: const BoxDecoration(
                                    color: KLPalette.mutedBg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: photoUrl.isNotEmpty
                                      ? ClipOval(
                                    child: Image.network(
                                      photoUrl,
                                      fit: BoxFit.cover,
                                      width: 84,
                                      height: 84,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.person,
                                        color: KLPalette.text2,
                                        size: 38,
                                      ),
                                    ),
                                  )
                                      : const Icon(Icons.person, color: KLPalette.text2, size: 38),
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: () async {
                                      final uid = FirebaseAuth.instance.currentUser?.uid;
                                      if (uid == null) return;

                                      try {
                                        final source = await showPhotoPickerSheet(context);
                                        if (source == null) return;

                                        final picked = await _picker.pickImage(
                                          source: source,
                                          imageQuality: 85,
                                          maxWidth: 1024,
                                        );
                                        if (picked == null) return;

                                        final url = await _photo.uploadProfilePhoto(
                                          uid: uid,
                                          file: File(picked.path),
                                          previousUrl: photoUrl,
                                        );

                                        // Update user doc (same as seeker)
                                        await _repo.updateMe({'photoUrl': url});

                                        if (!mounted) return;
                                        setState(() => photoUrl = url);

                                        AppSnack.show(
                                          context,
                                          "Profile photo updated",
                                          type: AppSnackType.success,
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        AppSnack.show(
                                          context,
                                          "Upload failed: $e",
                                          type: AppSnackType.error,
                                        );
                                      }
                                    },
                                    child: Container(
                                      height: 36,
                                      width: 36,
                                      decoration: BoxDecoration(
                                        color: KLPalette.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: KLPalette.border),
                                      ),
                                      child: const Icon(
                                        Icons.photo_camera_outlined,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          _LabeledField(
                            label: "Full Name",
                            controller: nameCtrl,
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 14),

                          // email read-only
                          const Text("Email", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 8),
                          TextField(
                            enabled: false,
                            controller: TextEditingController(text: email),
                            decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline)),
                          ),
                          const SizedBox(height: 14),

                          _LabeledField(
                            label: "Phone",
                            controller: phoneCtrl,
                            icon: Icons.phone_outlined,
                          ),
                          const SizedBox(height: 14),

                          const Text("Business Address", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 8),

                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ProviderBusinessAddressScreen()),
                              );
                              await _load();
                              if (!mounted) return;
                              // AppSnack.show(context, "Business address updated", type: AppSnackType.success);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: KLPalette.bg,
                                border: Border.all(color: KLPalette.border),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 44,
                                    width: 44,
                                    decoration: BoxDecoration(
                                      color: KLPalette.mutedBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: KLPalette.border),
                                    ),
                                    child: const Icon(Icons.place_outlined, color: KLPalette.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          addressCtrl.text.trim().isEmpty ? "No business address yet" : "Current business address",
                                          style: const TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          addressCtrl.text.trim().isEmpty
                                              ? "Tap to add & pin your location (required)"
                                              : addressCtrl.text.trim(),
                                          style: const TextStyle(
                                            color: KLPalette.text2,
                                            fontWeight: FontWeight.w700,
                                            height: 1.25,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          "Tap to manage address & pin",
                                          style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: KLPalette.text2),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 56,
                                  child: OutlinedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                    ),
                                    child: const Text(
                                      "Cancel",
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 56,
                                  child: FilledButton(
                                    onPressed: _save,
                                    style: FilledButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                    ),
                                    child: const Text(
                                      "Update",
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'name': nameCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'businessAddress': addressCtrl.text.trim(),
          'email': FirebaseAuth.instance.currentUser?.email,
          'role': 'provider',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      AppSnack.show(context, "Profile updated", type: AppSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(context, "Update failed: $e", type: AppSnackType.error);
    }
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(prefixIcon: Icon(icon)),
        ),
      ],
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