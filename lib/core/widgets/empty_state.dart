import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Empty list state: icon, message and one action (PRD E3 UI rules).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.gutter * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 32, color: AppColors.muted),
            ),
            const SizedBox(height: AppSizes.gutter),
            Text(title,
                style: textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSizes.gap),
            Text(
              message,
              style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSizes.gutter * 1.5),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
