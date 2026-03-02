import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import 'email_login_screen.dart';
import 'register_screen.dart';

class SignInMethodScreen extends StatelessWidget {
  const SignInMethodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // Top brand
              Row(
                children: const [
                  Spacer(),
                  Column(
                    children: [
                      Text(
                        "KLServeLink",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Find trusted services around you",
                        style: TextStyle(
                          color: KLPalette.text2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Spacer(),
                ],
              ),

              const SizedBox(height: 18),

              // Hero
              Expanded(
                child: Center(
                  child: Container(
                    height: 240,
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 360),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: KLPalette.border),
                    ),
                    child: Center(
                        child: Image.asset(
                          'assets/images/logo_full.png',
                          fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom card
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  decoration: BoxDecoration(
                    color: KLPalette.primary,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Let’s get started",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 30,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Sign in to book services, track bookings, and receive updates.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Email sign-in (primary)
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: KLPalette.darkPill,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.email_outlined),
                              SizedBox(width: 10),
                              Text(
                                "Continue with Email",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Create account
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RegisterScreen()),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_add_alt_1_rounded),
                              SizedBox(width: 10),
                              Text(
                                "Create an account",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        "By continuing, you agree to our Terms & Privacy Policy.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.3,
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