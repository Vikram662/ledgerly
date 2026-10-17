import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../i18n/i18n.dart';
import '../utils/money.dart';

/// Big on-screen numpad for rupee amounts (PRD E2 Advance Entry: 28px keys).
/// Keeps the value as text; read it with [parseRupeesToPaise].
class AmountPad extends StatelessWidget {
  const AmountPad({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowDecimal = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool allowDecimal;

  void _press(String key) {
    HapticFeedback.selectionClick();
    if (key == '⌫') {
      if (value.isNotEmpty) onChanged(value.substring(0, value.length - 1));
      return;
    }
    if (key == '.') {
      if (!allowDecimal || value.contains('.')) return;
      onChanged(value.isEmpty ? '0.' : '$value.');
      return;
    }
    final dot = value.indexOf('.');
    if (dot >= 0 && value.length - dot > 2) return; // max 2 decimals
    if (value == '0') {
      onChanged(key);
      return;
    }
    if (value.replaceAll('.', '').length >= 9) return;
    onChanged('$value$key');
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '⌫'],
    ];
    return Column(
      children: [
        for (final row in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.gap),
            child: Row(
              children: [
                for (final key in row) ...[
                  Expanded(
                    child: _PadKey(
                      label: key,
                      enabled: key != '.' || allowDecimal,
                      onTap: () => _press(key),
                    ),
                  ),
                  if (key != row.last) const SizedBox(width: AppSizes.gap),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isBackspace = label == '⌫';
    return Material(
      color: AppColors.page,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.input),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 60,
          child: Center(
            child: isBackspace
                ? Icon(Icons.backspace_outlined, semanticLabel: tr('Delete'))
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: enabled ? AppColors.ink : AppColors.faint,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Large amount display above an [AmountPad]: grey label, big amount,
/// optional caption (e.g. the new balance).
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({
    super.key,
    required this.text,
    this.label,
    this.caption,
    this.color = AppColors.ink,
  });

  final String text;
  final String? label;
  final String? caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final paise = parseRupeesToPaise(text);
    const grey = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.muted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(label ?? tr('Amount'), style: grey),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text.isEmpty ? '₹0' : (paise == null ? '₹$text' : formatPaise(paise)),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.4,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: text.isEmpty ? AppColors.faint : color,
              ),
            ),
          ),
          if (caption != null)
            Text(caption!, style: grey.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}
