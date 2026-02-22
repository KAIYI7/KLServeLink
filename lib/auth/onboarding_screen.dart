import 'package:flutter/material.dart';
import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final ctrl = PageController();
  int page = 0;

  final pages = const [
    _Onb(
      title: "Discover Local Experts",
      subtitle: "Instantly find and book top-rated professionals in the Kuala Lumpur for any task, right from your phone.",
      asset: "assets/images/onboarding/ob1.png",
    ),
    _Onb(
      title: "Smart and Seamless Booking",
      subtitle: "Our intelligent system matches you with the right services at the right time, making scheduling effortless.",
      asset: "assets/images/onboarding/ob2.png",
    ),
    _Onb(
      title: "Trusted by the Community",
      subtitle: "Make confident decisions with verified reviews and automated sentiment insights from real local customers.",
      asset: "assets/images/onboarding/ob3.png",
    ),
  ];

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = page == pages.length - 1;

    return Scaffold(
      backgroundColor: KLPalette.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: ctrl,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => page = i),
                itemBuilder: (_, i) => pages[i],
              ),
            ),

            const SizedBox(height: 8),

            // dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pages.length, (i) {
                final active = i == page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  height: 8,
                  width: active ? 26 : 8,
                  decoration: BoxDecoration(
                    color: active ? KLPalette.primary : KLPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),

            const SizedBox(height: 18),

            // circular next button
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  if (isLast) {
                    widget.onFinish();
                  } else {
                    ctrl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                  }
                },
                child: Container(
                  height: 78,
                  width: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: KLPalette.tint200, width: 6),
                  ),
                  child: Center(
                    child: Container(
                      height: 58,
                      width: 58,
                      decoration: const BoxDecoration(
                        color: KLPalette.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Onb extends StatelessWidget {
  final String title;
  final String subtitle;
  final String asset;

  const _Onb({required this.title, required this.subtitle, required this.asset});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top artwork area (keep simple; TODO : can add curved background later)
        Expanded(
          child: Center(
            child: Image.asset(asset, fit: BoxFit.contain),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 38, height: 1.05),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700, fontSize: 16, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}