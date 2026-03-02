import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/theme.dart';

class PhotoPickResult {
  final ImageSource source;
  const PhotoPickResult(this.source);
}

Future<ImageSource?> showPhotoPickerSheet(BuildContext context) async {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: (_) => const _PhotoPickerSheet(),
  );
}

class _PhotoPickerSheet extends StatelessWidget {
  const _PhotoPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Container(
            decoration: BoxDecoration(
              color: KLPalette.bg,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: KLPalette.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  height: 5,
                  width: 44,
                  decoration: BoxDecoration(
                    color: KLPalette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),

                const Text(
                  "Change profile photo",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    children: [
                      _SheetAction(
                        icon: Icons.photo_camera_outlined,
                        title: "Take photo",
                        subtitle: "Use camera",
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                      const SizedBox(height: 10),
                      _SheetAction(
                        icon: Icons.photo_library_outlined,
                        title: "Choose from gallery",
                        subtitle: "Pick existing photo",
                        onTap: () => Navigator.pop(context, ImageSource.gallery),
                      ),
                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            side: const BorderSide(color: KLPalette.border),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                      ),
                    ],
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

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
              decoration: BoxDecoration(
                color: KLPalette.tint100,
                shape: BoxShape.circle,
                border: Border.all(color: KLPalette.border),
              ),
              child: Icon(icon, color: KLPalette.primary700),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: KLPalette.text2, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: KLPalette.text2),
          ],
        ),
      ),
    );
  }
}