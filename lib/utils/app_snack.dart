import 'package:flutter/material.dart';
import '../theme.dart';

enum AppSnackType { info, success, error }

class AppSnack {
  static void show(
      BuildContext context,
      String message, {
        AppSnackType type = AppSnackType.info,
        Duration duration = const Duration(seconds: 2),
        double bottomOffset = 80,
      }) {
    if (!context.mounted) return;

    final scheme = _scheme(type);
    final sysBottom = MediaQuery.of(context).viewPadding.bottom;
    final bottomMargin = (sysBottom + bottomOffset - 50).clamp(0.0, double.infinity);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: duration,
          margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
          dismissDirection: DismissDirection.horizontal,
          content: _SnackBody(
            message: message,
            icon: scheme.icon,
            bg: scheme.bg,
            fg: scheme.fg,
            border: scheme.border,
          ),
        ),
      );
  }

  static _SnackScheme _scheme(AppSnackType type) {
    switch (type) {
      case AppSnackType.success:
        return _SnackScheme(
          icon: Icons.check_circle_rounded,
          bg: const Color(0xFFECFDF3),
          fg: const Color(0xFF15803D),
          border: const Color(0xFFBBF7D0),
        );
      case AppSnackType.error:
        return _SnackScheme(
          icon: Icons.error_rounded,
          bg: const Color(0xFFFFEEF0),
          fg: const Color(0xFFB91C1C),
          border: const Color(0xFFFECACA),
        );
      case AppSnackType.info:
      default:
        return _SnackScheme(
          icon: Icons.info_rounded,
          bg: KLPalette.mutedBg,
          fg: KLPalette.text,
          border: KLPalette.border,
        );
    }
  }
}

class _SnackScheme {
  final IconData icon;
  final Color bg;
  final Color fg;
  final Color border;
  const _SnackScheme({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.border,
  });
}

class _SnackBody extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color bg;
  final Color fg;
  final Color border;

  const _SnackBody({
    required this.message,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}