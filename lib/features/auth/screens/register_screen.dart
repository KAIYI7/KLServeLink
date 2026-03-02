import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import 'role_selection_onboarding_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool showPass = false;
  bool loading = false;
  String? errorText;

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String s) => RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s.trim());

  Future<void> _register() async {
    final name = nameCtrl.text.trim();
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text;

    setState(() => errorText = null);

    if (name.isEmpty) {
      setState(() => errorText = "Name is required.");
      return;
    }
    if (!_validEmail(email)) {
      setState(() => errorText = "Email format is invalid.");
      return;
    }
    if (pass.length < 6) {
      setState(() => errorText = "Password must be at least 6 characters.");
      return;
    }

    setState(() => loading = true);

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );

      await cred.user?.updateDisplayName(name);

      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': email,
        'role': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _RegisterSuccessDialog(),
      );

      if (ok == true && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionOnboardingScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'email-already-in-use' => 'This email is already registered.',
        'invalid-email' => 'Email is invalid.',
        'weak-password' => 'Password is too weak.',
        _ => 'Registration failed. Please try again.',
      };
      setState(() => errorText = msg);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).viewInsets.bottom + 18,),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 14),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Create Account",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 40, height: 1.05),
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Create your account to explore KLServeLink",
                  style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 16),

              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  decoration: BoxDecoration(
                    color: KLPalette.bg,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: KLPalette.border),
                  ),
                  child: Column(
                    children: [
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
                                  style: const TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Name", style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          hintText: "Input your name",
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        onChanged: (_) => setState(() => errorText = null),
                      ),
                      const SizedBox(height: 14),

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
                      const SizedBox(height: 14),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Password", style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.text)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: passCtrl,
                        obscureText: !showPass,
                        decoration: InputDecoration(
                          hintText: "Input your password",
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => showPass = !showPass),
                            icon: Icon(showPass ? Icons.visibility_off : Icons.visibility),
                          ),
                        ),
                        onChanged: (_) => setState(() => errorText = null),
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: loading ? null : _register,
                          child: loading
                              ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Text("Create Account", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),

                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Already have an account? ",
                            style: TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
                          ),
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              "Login",
                              style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700),
                            ),
                          ),
                        ],
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

class _RegisterSuccessDialog extends StatelessWidget {
  const _RegisterSuccessDialog();

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
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 14),
            const Text("Successful", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 30)),
            const SizedBox(height: 8),
            const Text(
              "Your account has been successfully registered.",
              textAlign: TextAlign.center,
              style: TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Continue", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}