import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../db/enums.dart';
import '../i18n/i18n.dart';

/// Bottom sheet list picker. Returns the chosen value or null.
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
  String Function(T)? subtitle,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(
                      title: Text(label(option)),
                      subtitle:
                          subtitle == null ? null : Text(subtitle(option)),
                      trailing: option == selected
                          ? const Icon(Icons.check, color: AppColors.successText)
                          : null,
                      onTap: () => Navigator.of(context).pop(option),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Read-only field that opens a picker when tapped (replaces dropdowns).
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              side: const BorderSide(color: AppColors.inputBorder),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.input),
              onTap: onTap,
              child: SizedBox(
                height: AppSizes.tapSecondary,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: AppColors.muted),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        value ?? tr('Choose'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: value == null ? AppColors.faint : AppColors.ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.expand_more, color: AppColors.muted),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String paymentModeLabel(PaymentMode mode) => switch (mode) {
      PaymentMode.cash => tr('Cash'),
      PaymentMode.phonePe => tr('PhonePe'),
      PaymentMode.paytm => tr('Paytm'),
      PaymentMode.gPay => tr('GPay'),
      PaymentMode.bank => tr('Bank'),
      PaymentMode.cheque => tr('Cheque'),
    };

/// Payment mode chips (PRD KH-01).
class PaymentModeChips extends StatelessWidget {
  const PaymentModeChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PaymentMode value;
  final ValueChanged<PaymentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final mode in PaymentMode.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSizes.gap),
              child: ChoiceChip(
                showCheckmark: false,
                label: Text(paymentModeLabel(mode)),
                selected: value == mode,
                onSelected: (_) => onChanged(mode),
              ),
            ),
        ],
      ),
    );
  }
}

Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
}) {
  final lastDate = last ?? DateTime.now().add(const Duration(days: 365));
  final firstDate = first ?? DateTime(2000);
  var initialDate = initial;
  if (initialDate.isAfter(lastDate)) initialDate = lastDate;
  if (initialDate.isBefore(firstDate)) initialDate = firstDate;
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  );
}
