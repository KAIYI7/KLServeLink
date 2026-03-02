import 'auth_gate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/theme.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  bool remember = false;
  bool showPass = false;
  bool loading = false;

  String? errorText;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('remember_email');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        emailCtrl.text = saved;
        remember = true;
      });
    }
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String s) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s.trim());
  }

  Future<void> _login() async {
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text;

    setState(() => errorText = null);

    if (!_validEmail(email)) {
      setState(() => errorText = "Your email is incorrect");
      return;
    }
    if (pass.length < 6) {
      setState(() => errorText = "Password must be at least 6 characters");
      return;
    }

    setState(() => loading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);

      final prefs = await SharedPreferences.getInstance();
      if (remember) {
        await prefs.setString('remember_email', email);
      } else {
        await prefs.remove('remember_email');
      }

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'user-not-found' => 'No account found for this email.',
        'wrong-password' => 'Incorrect password.',
        'invalid-credential' => 'Invalid email or password.',
        'user-disabled' => 'This account has been disabled.',
        _ => 'Login failed. Please try again.',
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: SingleChildScrollView(
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
                const SizedBox(height: 14),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Hi, Welcome Back 👋",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34, height: 1.05),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Sign in to your account",
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
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            InkWell(
                              onTap: () => setState(() => remember = !remember),
                              borderRadius: BorderRadius.circular(10),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: remember,
                                    onChanged: (v) => setState(() => remember = v ?? false),
                                  ),
                                  const Text(
                                    "Remember me",
                                    style: TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                );
                              },
                              child: const Text(
                                "Forgot Password?",
                                style: TextStyle(fontWeight: FontWeight.w900, color: KLPalette.primary700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton(
                            onPressed: loading ? null : _login,
                            child: loading
                                ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                                : const Text("Login", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don’t have an account? ",
                              style: TextStyle(fontWeight: FontWeight.w800, color: KLPalette.text2),
                            ),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                );
                              },
                              child: const Text(
                                "Register",
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
      ),
    );
  }
}