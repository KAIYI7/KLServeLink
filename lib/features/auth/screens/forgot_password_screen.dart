import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailCtrl = TextEditingController();
  bool loading = false;
  String? errorText;

  @override
  void dispose() {
    emailCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String s) => RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s.trim());

  Future<void> _send() async {
    final email = emailCtrl.text.trim();
    setState(() => errorText = null);

    if (!_validEmail(email)) {
      setState(() => errorText = "Email format is invalid.");
      return;
    }

    setState(() => loading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _EmailSentDialog(),
      );

      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (_) {
      // For security, don't reveal if email exists or not
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _EmailSentDialog(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => loading = false);
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
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
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
                  const Text("KLServeLink", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 16),

              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  decoration: BoxDecoration(
                    color: KLPalette.bg,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: KLPalette.border),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Reset Your Password",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34, height: 1.05),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Enter your email and we will send a password reset link.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
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

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Email", style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: "Input your email",
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                        onChanged: (_) => setState(() => errorText = null),
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: loading ? null : _send,
                          child: loading
                              ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Text("Send Reset Link", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                    ],
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

class _EmailSentDialog extends StatelessWidget {
  const _EmailSentDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 96,
              width: 96,
              decoration: const BoxDecoration(
                color: KLPalette.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 14),
            const Text("Check your email",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28)),
            const SizedBox(height: 8),
            const Text(
              "If this email is registered, a reset link has been sent.\nPlease open your inbox to continue.",
              textAlign: TextAlign.center,
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Okay", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}