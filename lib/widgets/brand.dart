import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class TicketXBrand extends StatelessWidget {
  const TicketXBrand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          'assets/icon/app_icon.png',
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: 8),
      const Text(
        'TiketiX',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 21,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(width: 10),
      const SizedBox(
        height: 22,
        child: VerticalDivider(color: AppColors.border),
      ),
      const Text(
        'SCANNER',
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 27,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: const TextStyle(color: AppColors.muted, height: 1.35),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}
