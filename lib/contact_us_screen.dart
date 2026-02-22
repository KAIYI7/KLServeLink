import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fyp_flutter/utils/app_snack.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  static const String appName = "KLServeLink";
  static const String supportEmail = "support@klservelink.com";
  static const String phoneNumber = "+60164994523";
  static const String websiteUrl = "https://klservelink.com";
  static const String companyName = "KLServeLink SDN BHD";
  static const String companyAddress =
      "Lot 10, Jalan Prima Setapak,\n53300 Kuala Lumpur,\nMalaysia";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            children: [
              _TopBar(title: "Contact Us", onBack: () => Navigator.pop(context)),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    _InfoCard(
                      title: "About $appName",
                      subtitle:
                      "A service marketplace app that connects seekers with verified providers.\n\n"
                          "Need help? Contact support using the options below.",
                      icon: Icons.info_outline_rounded,
                    ),
                    const SizedBox(height: 12),

                    _SectionTitle("Support"),
                    const SizedBox(height: 10),

                    _Row(
                      icon: Icons.email_outlined,
                      title: "Email Support",
                      subtitle: supportEmail,
                      onTap: () => _email(
                        context,
                        to: supportEmail,
                        subject: "Support request ($appName)",
                        body:
                        "Hi $appName Support,\n\n"
                            "I need help with:\n"
                            "- Issue: \n"
                            "- Booking/Service ID (if any): \n"
                            "- Steps to reproduce: \n\n"
                            "Thanks.",
                      ),
                      trailing: "Open",
                    ),
                    const SizedBox(height: 12),

                    _Row(
                      icon: Icons.feedback_outlined,
                      title: "Send Feedback",
                      subtitle: "Suggest improvements or report bugs",
                      onTap: () => _email(
                        context,
                        to: supportEmail,
                        subject: "Feedback ($appName)",
                        body:
                        "Hi $appName Team,\n\n"
                            "Feedback:\n"
                            "- What I like:\n"
                            "- What can be improved:\n"
                            "- Bug details (if any):\n\n"
                            "Thanks!",
                      ),
                      trailing: "Open",
                    ),
                    const SizedBox(height: 12),

                    _Row(
                      icon: Icons.call_outlined,
                      title: "Call",
                      subtitle: phoneNumber,
                      onTap: () => _call(context, phoneNumber),
                      trailing: "Dial",
                    ),
                    const SizedBox(height: 18),

                    _SectionTitle("Company"),
                    const SizedBox(height: 10),

                    _Row(
                      icon: Icons.location_on_outlined,
                      title: "Address",
                      subtitle: companyAddress,
                      onTap: () => _copy(context, companyAddress),
                      trailing: "Copy",
                    ),
                    const SizedBox(height: 12),

                    _Row(
                      icon: Icons.public,
                      title: "Website",
                      subtitle: websiteUrl,
                      onTap: () => _openUrl(context, websiteUrl),
                      trailing: "Open",
                    ),

                    const SizedBox(height: 18),
                    _InfoCard(
                      title: "Operating hours",
                      subtitle: "Mon–Fri, 9:00 AM – 6:00 PM (MYT)\n"
                          "We reply within 1–2 business days.",
                      icon: Icons.schedule_outlined,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Actions ---

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast(context, "Copied to clipboard");
  }

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: "tel", path: phone);
    await _launch(context, uri);
  }

  Future<void> _email(
      BuildContext context, {
        required String to,
        String? subject,
        String? body,
      }) async {
    final uri = Uri(
      scheme: "mailto",
      path: to,
      queryParameters: <String, String>{
        if (subject != null) "subject": subject,
        if (body != null) "body": body,
      },
    );
    await _launch(context, uri);
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast(context, "Invalid URL");
      return;
    }
    await _launch(context, uri);
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      _toast(context, "Cannot open this on your device");
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _toast(BuildContext context, String msg) {
    AppSnack.show(context, msg, type: AppSnackType.info);
  }
}

// --- UI bits ---

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KLPalette.tint50,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: KLPalette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: KLPalette.bg,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: Icon(icon, color: KLPalette.primary700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String trailing;

  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
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
              decoration: const BoxDecoration(
                color: KLPalette.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: KLPalette.tint50,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: KLPalette.border),
              ),
              child: Text(
                trailing,
                style: const TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700),
              ),
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