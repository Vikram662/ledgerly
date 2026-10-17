import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../i18n/i18n.dart';
import '../utils/money.dart';

export 'shimmer.dart';

// Getters, so dates follow the current UI language.
DateFormat get dayFormat => DateFormat('d MMM yyyy', uiDateLocale);
DateFormat get dayTimeFormat => DateFormat('d MMM, h:mm a', uiDateLocale);
DateFormat get monthFormat => DateFormat('MMMM yyyy', uiDateLocale);

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: AppColors.dangerText)
              : null,
          child: Text(confirmLabel ?? tr('Yes')),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Status pill with icon + label, never color alone (PRD I-D3).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Label / amount row used in summaries.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.paise,
    this.color,
    this.bold = false,
    this.prefix = '',
  });

  final String label;
  final int paise;
  final Color? color;
  final bool bold;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final style = AppText.tabular.copyWith(
      fontSize: bold ? 18 : 15,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 16 : 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ),
          Text('$prefix${formatPaise(paise)}', style: style),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSizes.gutter, 0, AppSizes.gap),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// White rounded card with a hairline border, flat (no shadow).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSizes.gutter),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// A card of rows separated by hairlines (lists of workers, bills, entries).
class CardList extends StatelessWidget {
  const CardList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 44px round icon button with a hairline border (back, menu, bell).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(AppSizes.iconButton),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.border),
      ),
    );
  }
}

/// Round avatar with up to two initials ("Raju Kumar" → "RK").
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.track,
        shape: BoxShape.circle,
      ),
      child: Text(
        twoInitials(name),
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.w700,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// Back button, a segmented progress bar and "2 / 3" (onboarding steps).
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.step,
    required this.total,
    this.onBack,
  });

  final int step;
  final int total;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          AppIconButton(
            icon: Icons.arrow_back,
            tooltip: tr('Back'),
            onPressed: onBack,
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Semantics(
            label: tr('Step {step} of {total}', {'step': step, 'total': total}),
            child: Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i < step ? AppColors.primary : AppColors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$step / $total',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

/// Dark rounded tile with the business initial in amber (Home, Unlock).
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, required this.name, this.size = 72});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: AppColors.amberLogo,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Small bold label above a form field, with an optional "(optional)".
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.optional = false});

  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (optional)
              TextSpan(
                text: ' ${tr('(optional)')}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.muted),
              ),
          ],
        ),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// Form field with its label above it (wireframe forms), and an optional
/// grey help line under it.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.optional = false,
    this.help,
    this.bottomGap = 14,
  });

  final String label;
  final Widget child;
  final bool optional;
  final String? help;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FieldLabel(label, optional: optional),
          child,
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                help!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tappable read-only field (date, picker) styled like an input.
class TapField extends StatelessWidget {
  const TapField({
    super.key,
    required this.value,
    required this.onTap,
    this.icon = Icons.calendar_today_outlined,
    this.placeholder,
  });

  final String? value;
  final VoidCallback onTap;
  final IconData icon;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        side: const BorderSide(color: AppColors.inputBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.input),
        onTap: onTap,
        child: Container(
          height: AppSizes.tapSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value ?? placeholder ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: value == null ? AppColors.faint : AppColors.ink,
                  ),
                ),
              ),
              Icon(icon, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// White card showing a choice (client, bill, worker) with "Change".
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.leading,
    required this.title,
    required this.onTap,
    this.overline,
    this.subtitle,
  });

  final Widget leading;
  final String title;
  final String? overline;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const grey = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
    );
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (overline != null) Text(overline!, style: grey),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.tabular
                          .copyWith(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: AppText.tabular.merge(grey)),
                  ],
                ),
              ),
              Text(
                tr('Change'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big screen heading with an optional muted line under it.
class ScreenHeading extends StatelessWidget {
  const ScreenHeading(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// Header of a bottom-tab screen: big 24px title, no back button.
AppBar tabAppBar(
  String title, {
  List<Widget>? actions,
  Widget? subtitle,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    automaticallyImplyLeading: false,
    titleSpacing: AppSizes.gutter,
    title: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.48,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const Spacer(),
          DefaultTextStyle.merge(
            style: AppText.tabular.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
            child: subtitle,
          ),
        ],
      ],
    ),
    actions: [
      ...?actions,
      const SizedBox(width: 8),
    ],
    bottom: bottom,
  );
}

/// Grey track with equal segments; the selected one is a white pill.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.track,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: Semantics(
                selected: entry.key == value,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.key == value
                          ? AppColors.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: entry.key == value
                          ? const [
                              BoxShadow(
                                color: Color(0x14101828),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: entry.key == value
                            ? AppColors.ink
                            : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// White card: previous month, "October 2026", next month.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onShift,
    this.canGoNext = true,
  });

  final DateTime month;
  final ValueChanged<int> onShift;
  final bool canGoNext;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          IconButton(
            tooltip: tr('Previous month'),
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onShift(-1),
          ),
          Expanded(
            child: Text(
              monthFormat.format(month),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: tr('Next month'),
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoNext ? () => onShift(1) : null,
          ),
        ],
      ),
    );
  }
}

/// 44px white outlined button with an icon (secondary actions in a row).
class SmallOutlinedButton extends StatelessWidget {
  const SmallOutlinedButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// 36px round − / + button for steppers.
class StepButton extends StatelessWidget {
  const StepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(36),
        minimumSize: const Size.square(36),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.border),
      ),
    );
  }
}

/// Small uppercase grey label above a group of cards ("WORK", "MONEY").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.72,
                color: AppColors.muted,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Grey rounded square holding an icon (list rows, tiles).
class IconTile extends StatelessWidget {
  const IconTile(
    this.icon, {
    super.key,
    this.size = 40,
    this.color = AppColors.page,
    this.iconColor = AppColors.ink,
  });

  final IconData icon;
  final double size;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.5, color: iconColor),
    );
  }
}

/// Card tile for a 2-column grid: icon, bold label, grey detail.
class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              Text(
                detail ?? ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays tiles out two per row with 8px gaps.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 56px settings row: icon tile, label, optional value and chevron.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.valueColor = AppColors.muted,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? value;
  final Color valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconTile(icon, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                Text(
                  value!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.faint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Month over day number in a small rounded tile (task and bill rows).
class DateTile extends StatelessWidget {
  const DateTile({super.key, required this.date, this.danger = false});

  final DateTime date;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? AppColors.dangerText : AppColors.ink;
    return Container(
      width: 44,
      height: 48,
      decoration: BoxDecoration(
        color: danger ? AppColors.dangerSurface : AppColors.page,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('MMM', uiDateLocale).format(date).toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: danger ? fg : AppColors.muted,
            ),
          ),
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 17,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small coloured badge ("PRO", "FREE", "Overdue").
class TagBadge extends StatelessWidget {
  const TagBadge(
    this.text, {
    super.key,
    this.color = AppColors.amber100,
    this.textColor = const Color(0xFF92400E),
  });

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }
}

/// Grey search field with a magnifier (lists).
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, color: AppColors.muted),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

/// Sticky bottom bar with one primary button (56px, PRD E3).
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.top,
    this.summaryLabel,
    this.summaryValue,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Widget? top;

  /// Optional total shown left of the button ("Amount ₹9,240").
  final String? summaryLabel;
  final String? summaryValue;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : Text(label),
    );
    if (summaryValue != null) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (top != null) top!,
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (summaryLabel != null)
                            Text(
                              summaryLabel!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              summaryValue!,
                              style: AppText.tabular.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: button),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (top != null) top!,
              FilledButton(
                onPressed: busy ? null : onPressed,
                child: busy
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String initials(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}

/// First letters of the first two words, upper case.
String twoInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}
