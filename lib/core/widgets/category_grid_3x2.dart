import 'package:flutter/material.dart';
import '../models/service_category.dart';
import '../theme/theme.dart';

class CategoryGrid3x2 extends StatelessWidget {
  final void Function(ServiceCategory cat) onTap;
  const CategoryGrid3x2({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final topRow = kCategories.take(3).toList();
    final bottomRow = kCategories.skip(3).take(2).toList();

    return Column(
      children: [
        // ── Top row (3 equal items)
        Row(
          children: [
            Expanded(
              child: _CategoryTile(
                meta: topRow[0],
                onTap: () => onTap(topRow[0].id),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CategoryTile(
                meta: topRow[1],
                onTap: () => onTap(topRow[1].id),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CategoryTile(
                meta: topRow[2],
                onTap: () => onTap(topRow[2].id),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── Bottom row (2 centered items)
        Row(
          children: [
            const Spacer(),
            Expanded(
              flex: 4,
              child: _CategoryTile(
                meta: bottomRow[0],
                onTap: () => onTap(bottomRow[0].id),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: _CategoryTile(
                meta: bottomRow[1],
                onTap: () => onTap(bottomRow[1].id),
              ),
            ),
            const Spacer(),
          ],
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final CategoryMeta meta;
  final VoidCallback onTap;
  const _CategoryTile({required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KLPalette.mutedBg,
              border: Border.all(color: KLPalette.border),
            ),
            child: Icon(meta.icon, color: KLPalette.primary),
          ),
          const SizedBox(height: 10),
          Text(
            meta.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}