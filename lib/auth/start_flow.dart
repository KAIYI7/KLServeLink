import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_screen.dart';
import 'sign_in_method_screen.dart';

class StartFlow extends StatefulWidget {
  const StartFlow({super.key});

  @override
  State<StartFlow> createState() => _StartFlowState();
}

class _StartFlowState extends State<StartFlow> {
  bool? seen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => seen = prefs.getBool('seen_onboarding') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    if (seen == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (seen == true) {
      return const SignInMethodScreen();
    }

    return OnboardingScreen(
      onFinish: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('seen_onboarding', true);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SignInMethodScreen()),
        );
      },
    );
  }
}