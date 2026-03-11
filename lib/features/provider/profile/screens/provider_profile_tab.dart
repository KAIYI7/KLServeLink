import 'dart:io';
import 'package:fyp_flutter/core/utils/app_snack.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/theme.dart';
import 'provider_edit_profile_screen.dart';
import '../../../notifications/screens/notification_settings_screen.dart';
import '../../../user/screens/security_screen.dart';
import '../../../user/screens/contact_us_screen.dart';
import 'provider_business_address_screen.dart';
import 'provider_service_areas_screen.dart';
import 'provider_payout_screen.dart';
import 'provider_working_hours_screen.dart';

import '../../../user/data/user_profile_repo.dart';
import '../../../../core/services/profile_photo_service.dart';
import '../../../../core/widgets/photo_picker_sheet.dart';

class ProviderProfileTab extends StatefulWidget {
  const ProviderProfileTab({super.key});

  @override
  State<ProviderProfileTab> createState() => _ProviderProfileTabState();
}

class _ProviderProfileTabState extends State<ProviderProfileTab> {
  bool darkTheme = false;

  final _repo = UserProfileRepo();
  final _photo = ProfilePhotoService();
  final _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              Row(
                children: const [
                  SizedBox(width: 48),
                  Spacer(),
                  Text("Profile", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  Spacer(),
                  SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 18),

              if (uid == null)
                const Center(child: Text("Please login"))
              else
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                  builder: (context, snap) {
                    final data = snap.data?.data();
                    final name = (data?['name'] ?? 'Provider') as String;
                    final email = (data?['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '-') as String;
                    final photoUrl = (data?['photoUrl'] ?? '').toString().trim();

                    return Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 74,
                              width: 74,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: KLPalette.mutedBg,
                              ),
                              child: photoUrl.isNotEmpty
                                  ? ClipOval(
                                child: Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  width: 74,
                                  height: 74,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.person,
                                    size: 34,
                                    color: KLPalette.text2,
                                  ),
                                ),
                              )
                                  : const Icon(Icons.person, size: 34, color: KLPalette.text2),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: _CircleMini(
                                icon: Icons.photo_camera_outlined,
                                onTap: () async {
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

                                    await _repo.updateMe({'photoUrl': url});

                                    if (!mounted) return;
                                    AppSnack.show(context, "Profile photo updated", type: AppSnackType.success);
                                  } catch (e) {
                                    if (!mounted) return;
                                    AppSnack.show(context, "Upload failed: $e", type: AppSnackType.error);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        _CircleIconButton(
                          icon: Icons.settings_outlined,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ProviderEditProfileScreen()),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),

              const SizedBox(height: 18),

              const Text("General", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 12),

              _SettingRow(
                icon: Icons.notifications_none_rounded,
                title: "Notification",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              _SettingRow(
                icon: Icons.verified_user_outlined,
                title: "Security",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SecurityScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              // _SettingSwitchRow(
              //   icon: Icons.dark_mode_outlined,
              //   title: "Dark Theme",
              //   value: darkTheme,
              //   onChanged: (v) => setState(() => darkTheme = v),
              // ),
              // const SizedBox(height: 12),

              _SettingRow(
                icon: Icons.info_outline_rounded,
                title: "Contact Us",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactUsScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 18),
              const Text("Provider Settings", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 12),

              _SettingRow(
                icon: Icons.business_outlined,
                title: "Business Address",
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderBusinessAddressScreen()));
                },
              ),
              const SizedBox(height: 12),

              _SettingRow(
                icon: Icons.map_outlined,
                title: "Service Coverage",
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderServiceAreasScreen()));
                },
              ),
              const SizedBox(height: 12),

              _SettingRow(
                icon: Icons.account_balance_outlined,
                title: "Payout / Bank Info",
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderPayoutScreen()));
                },
              ),
              const SizedBox(height: 12),

              _SettingRow(
                icon: Icons.schedule_outlined,
                title: "Working Hours",
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderWorkingHoursScreen()));
                },
              ),

              const SizedBox(height: 12),
              _SettingRow(
                icon: Icons.logout_rounded,
                title: "Logout",
                danger: true,
                onTap: () => _showLogoutDialog(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _LogoutDialog(),
    );

    if (ok == true && mounted) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        if (!mounted) return;
        AppSnack.show(
          context,
          "Logout failed. Please try again.",
          type: AppSnackType.error,
        );
      }
    }
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger ? const Color(0xFFEF4444) : KLPalette.text;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: KLPalette.mutedBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
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
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: fg),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 18, color: fg.withOpacity(0.75)),
          ],
        ),
      ),
    );
  }
}

class _SettingSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: KLPalette.mutedBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: KLPalette.border),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: KLPalette.darkPill,
              shape: BoxShape.circle,
              border: Border.all(color: KLPalette.border),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
          Switch(
            value: value,
            activeColor: KLPalette.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 56,
        width: 56,
        decoration: BoxDecoration(
          color: KLPalette.tint100,
          shape: BoxShape.circle,
          border: Border.all(color: KLPalette.border),
        ),
        child: Icon(icon, color: KLPalette.primary700),
      ),
    );
  }
}

class _CircleMini extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleMini({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 34,
        width: 34,
        decoration: BoxDecoration(
          color: KLPalette.primary,
          shape: BoxShape.circle,
          border: Border.all(color: KLPalette.border),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Logout?",
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w900,
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Are you sure to want logout?",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        side: const BorderSide(color: KLPalette.border),
                      ),
                      child: const Text("Cancel",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: KLPalette.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text("Logout",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}