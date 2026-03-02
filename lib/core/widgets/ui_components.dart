import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final double size;
  final Widget? badge;

  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.filled = false,
    this.size = 52,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? KLPalette.primary : KLPalette.bg;
    final fg = filled ? Colors.white : KLPalette.text;
    final b = badge;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: size,
            width: size,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: filled ? null : Border.all(color: KLPalette.border),
            ),
            child: Icon(icon, color: fg),
          ),

          if (b != null) Positioned(right: -1, top: -1, child: b),
        ],
      ),
    );
  }
}

class NotificationDot extends StatelessWidget {
  const NotificationDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      width: 12,
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        shape: BoxShape.circle,
        border: Border.all(color: KLPalette.bg, width: 2),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const SectionHeader({super.key, required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSeeAll,
          child: const Row(
            children: [
              Text("See All", style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class GlassBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  final List<IconData> icons;

  const GlassBottomNav({super.key, required this.index, required this.onChanged, required this.icons,});

  @override
  Widget build(BuildContext context) {
    assert(icons.length >= 3 && icons.length <= 7, "GlassBottomNav expects 3–7 icons.");

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.75),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: KLPalette.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(icons.length, (i) {
                  final selected = i == index;
                  return GestureDetector(
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 48,
                      width: ((MediaQuery.of(context).size.width - 40 /*outer padding*/ - 20 /*inner padding*/ ) / icons.length).clamp(46, 56),
                      decoration: BoxDecoration(
                        color: selected ? KLPalette.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        icons[i],
                        color: selected ? Colors.white : KLPalette.text,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
