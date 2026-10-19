import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../i18n/i18n.dart';
import '../utils/money.dart';
import '../utils/photo_store.dart';

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

/// Colours of a badge. Each tone pairs a pale fill with the dark text colour
/// made for it, so badge text is always readable (PRD I-D1). Badges take a
/// tone, never free colours.
enum BadgeTone {
  neutral(AppColors.page, AppColors.inkSoft),
  info(AppColors.primaryTint, AppColors.primary),
  success(AppColors.successSurface, AppColors.successText),
  warning(AppColors.warningSurface, AppColors.warningText),
  danger(AppColors.dangerSurface, AppColors.dangerText),
  pro(AppColors.amber100, Color(0xFF92400E));

  const BadgeTone(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// The one badge / status pill / tag of the app (wireframe `.pill`, `.tag`):
/// 11px bold text on a pale fill, optional icon.
class AppBadge extends StatelessWidget {
  const AppBadge(
    this.text, {
    super.key,
    this.tone = BadgeTone.neutral,
    this.icon,
  });

  final String text;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone.foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.tabular.copyWith(
                color: tone.foreground,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one filter / choice chip (wireframe `.chip`, `.mode`): white with a
/// hairline border; selected is solid ink with white text.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(color: selected ? AppColors.ink : AppColors.border),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.ink : AppColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: AppText.tabular.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of [AppChip]s that scrolls sideways (filters, payment modes).
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSizes.gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Coloured dot with a label, for legends under bars and grids.
class LegendDot extends StatelessWidget {
  const LegendDot({
    super.key,
    required this.color,
    required this.label,
    this.labelColor = AppColors.muted,
    this.square = false,
  });

  final Color color;
  final String label;
  final Color labelColor;

  /// A 16px rounded square (cell legends) instead of an 8px dot.
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: square ? 16 : 8,
          height: square ? 16 : 8,
          decoration: BoxDecoration(
            color: color,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: square ? BorderRadius.circular(5) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppText.tabular.copyWith(
            fontSize: square ? 12 : 11,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
      ],
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

/// Consistent Indian country-code prefix for mobile number fields.
class PhoneCountryCode extends StatelessWidget {
  const PhoneCountryCode({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 58,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border)),
        ),
        child: const Text(
          '+91',
          style: TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

/// Up to two initials ("Raju Kumar" → "RK") in a grey circle, or the
/// person's photo when [photo] (a stored photo name) is set. [radius] makes
/// it a rounded square instead.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(
    this.name, {
    super.key,
    this.size = 40,
    this.photo,
    this.radius,
  });

  final String name;
  final double size;
  final String? photo;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: AppColors.track,
      shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: radius == null ? null : BorderRadius.circular(radius!),
    );
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: decoration,
      child: Text(
        twoInitials(name),
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.w700,
          color: AppColors.inkSoft,
        ),
      ),
    );
    if (photo == null) return initials;
    return FutureBuilder<File>(
      future: photoFile(photo!),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null || !file.existsSync()) return initials;
        return Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: decoration,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(),
          ),
        );
      },
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
    this.actionLabel,
  });

  final Widget leading;
  final String title;
  final String? overline;
  final String? subtitle;
  final VoidCallback onTap;

  /// Defaults to "Change".
  final String? actionLabel;

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
                actionLabel ?? tr('Change'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.headlineSmall),
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

/// Underlined section tabs above the content of a page (wireframe `.under`):
/// Billing, Client detail, Job detail. Styled by the app's TabBar theme.
class UnderlineTabs<T> extends StatelessWidget {
  const UnderlineTabs({
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
    final keys = options.keys.toList();
    return DefaultTabController(
      // A new controller when the set of tabs changes.
      key: ValueKey(keys.length),
      length: keys.length,
      initialIndex: keys.indexOf(value).clamp(0, keys.length - 1),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.only(right: 20),
        onTap: (i) => onChanged(keys[i]),
        tabs: [for (final label in options.values) Tab(text: label)],
      ),
    );
  }
}

/// Row of equal 48px action buttons; the first is the primary one
/// (wireframe `.act`: "+ New bill", "+ Payment", "+ Job").
class ActionButtons extends StatelessWidget {
  const ActionButtons({super.key, required this.actions});

  final List<({String label, VoidCallback onTap})> actions;

  @override
  Widget build(BuildContext context) {
    const size = Size(0, 48);
    const text = TextStyle(fontSize: 14, fontWeight: FontWeight.w800);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSizes.gap),
          Expanded(
            child: i == 0
                ? FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: size,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: shape,
                      textStyle: text,
                    ),
                    onPressed: actions[i].onTap,
                    child: Text(actions[i].label, maxLines: 1),
                  )
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: size,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: AppColors.ink,
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                      shape: shape,
                      textStyle: text,
                    ),
                    onPressed: actions[i].onTap,
                    child: Text(actions[i].label, maxLines: 1),
                  ),
          ),
        ],
      ],
    );
  }
}

/// Label over a figure, for a row of totals (Billed / Received / Pending).
class FigureColumn extends StatelessWidget {
  const FigureColumn({
    super.key,
    required this.label,
    required this.value,
    this.color = AppColors.ink,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.tabular.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 32px outlined button inside a row (wireframe `.mini`): Call, WhatsApp,
/// Send reminder.
class MiniButton extends StatelessWidget {
  const MiniButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      onPressed: onTap,
      child: Text(label),
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

/// Dark summary card at the top of a list: label, big amount, note and
/// an optional footer (wireframes Khata, Suppliers).
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.footer,
  });

  final String label;
  final String value;
  final String? note;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    const soft = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.inputBorder,
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: soft),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.tabular.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: Colors.white,
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: soft.copyWith(fontSize: 12)),
          ],
          if (footer != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF2E333B))),
              ),
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

/// 36px rounded tag with a short text, e.g. "P" or "In" (wireframe `.tag`).
class LetterTag extends StatelessWidget {
  const LetterTag(
    this.text, {
    super.key,
    this.color = AppColors.page,
    this.textColor = AppColors.ink,
  });

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
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
    this.icon,
    required this.label,
    this.subtitle,
    this.value,
    this.valueColor = AppColors.muted,
    this.trailing,
    this.onTap,
  });

  /// Null for plain rows (wireframe App lock).
  final IconData? icon;
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
              if (icon != null) ...[
                IconTile(icon!, size: 32),
                const SizedBox(width: 12),
              ],
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
    this.bottom,
    this.summaryLabel,
    this.summaryValue,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Widget? top;

  /// Shown under the button, e.g. secondary links.
  final Widget? bottom;

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
              button,
              if (bottom != null) bottom!,
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

/// Grey note field with the entry's date as a button on the right
/// (wireframe Payment / Advance / Expense entry).
class NoteDateField extends StatelessWidget {
  const NoteDateField({
    super.key,
    required this.controller,
    required this.dateLabel,
    required this.onPickDate,
    this.hint,
  });

  final TextEditingController controller;
  final String dateLabel;
  final VoidCallback onPickDate;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.small),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint ?? tr('Note (optional)'),
        isDense: true,
        filled: true,
        fillColor: AppColors.page,
        prefixIcon: const Icon(Icons.edit_note, color: AppColors.muted),
        border: border,
        enabledBorder: border,
        suffixIcon: TextButton(
          onPressed: onPickDate,
          child: Text(
            dateLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// "Today" or the short date, for a date button.
String dayButtonLabel(DateTime date) => DateUtils.isSameDay(date, DateTime.now())
    ? tr('Today')
    : dayFormat.format(date);
