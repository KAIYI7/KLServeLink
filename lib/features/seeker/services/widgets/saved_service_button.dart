import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/core/theme/theme.dart';
import 'package:fyp_flutter/core/utils/app_snack.dart';
import '../data/saved_services_repo.dart';

class SavedServiceButton extends StatelessWidget {
  final String serviceId;
  final bool? isSaved;
  final double size;
  final Color backgroundColor;
  final Color savedBackgroundColor;
  final Color iconColor;
  final Color savedIconColor;

  const SavedServiceButton({
    super.key,
    required this.serviceId,
    this.isSaved,
    this.size = 44,
    this.backgroundColor = Colors.white,
    this.savedBackgroundColor = KLPalette.tint50,
    this.iconColor = KLPalette.text,
    this.savedIconColor = KLPalette.primary,
  });

  Future<void> _toggle(BuildContext context) async {
    try {
      final nowSaved = await SavedServicesRepo().toggle(serviceId);

      if (!context.mounted) return;

      AppSnack.show(
        context,
        nowSaved ? "Service saved." : "Service removed from saved.",
        type: AppSnackType.success,
      );
    } on FirebaseAuthException {
      if (!context.mounted) return;
      AppSnack.show(
        context,
        "Please login first.",
        type: AppSnackType.info,
      );
    } catch (_) {
      if (!context.mounted) return;
      AppSnack.show(
        context,
        "Failed to update saved service.",
        type: AppSnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isSaved != null) {
      return _SaveIconShell(
        isSaved: isSaved!,
        size: size,
        backgroundColor: backgroundColor,
        savedBackgroundColor: savedBackgroundColor,
        iconColor: iconColor,
        savedIconColor: savedIconColor,
        onTap: () => _toggle(context),
      );
    }

    return StreamBuilder<bool>(
      stream: SavedServicesRepo().streamIsSaved(serviceId),
      builder: (context, snap) {
        final saved = snap.data ?? false;

        return _SaveIconShell(
          isSaved: saved,
          size: size,
          backgroundColor: backgroundColor,
          savedBackgroundColor: savedBackgroundColor,
          iconColor: iconColor,
          savedIconColor: savedIconColor,
          onTap: () => _toggle(context),
        );
      },
    );
  }
}

class _SaveIconShell extends StatelessWidget {
  final bool isSaved;
  final double size;
  final Color backgroundColor;
  final Color savedBackgroundColor;
  final Color iconColor;
  final Color savedIconColor;
  final VoidCallback onTap;

  const _SaveIconShell({
    required this.isSaved,
    required this.size,
    required this.backgroundColor,
    required this.savedBackgroundColor,
    required this.iconColor,
    required this.savedIconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSaved ? savedBackgroundColor : backgroundColor;
    final fg = isSaved ? savedIconColor : iconColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: size,
          width: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: KLPalette.border),
          ),
          child: Icon(
            isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: fg,
            size: size * 0.48,
          ),
        ),
      ),
    );
  }
}
