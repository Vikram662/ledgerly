import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/language_picker.dart';
import '../../subscription/subscription_controller.dart';
import '../data/onboarding_repository.dart';

/// First launch (wireframes A1–A3): Welcome, then "Who will use this app?"
/// (PRD C10), then name, phone and, for a contractor, trades (C0 TR-01).
/// Step 3, the PIN, is the lock gate's PIN setup screen.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, type, details }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _trades = <Trade>{};
  var _step = _Step.welcome;
  UserType? _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_refresh);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _go(_Step step) => setState(() => _step = step);

  bool get _canSave =>
      !_saving &&
      _type != null &&
      _name.text.trim().isNotEmpty &&
      (!_type!.usesTrades || _trades.isNotEmpty);

  void _toggle(Trade trade) {
    setState(() {
      if (!_trades.remove(trade)) _trades.add(trade);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(onboardingRepositoryProvider).complete(
            userType: _type!,
            businessName: _name.text.trim(),
            phone: normalizeIndianPhone(_phone.text),
            trades: _trades,
          );
      unawaited(ref.read(subscriptionControllerProvider.notifier).refresh());
      if (!mounted) return;
      context.go(Routes.dashboard);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(
        context,
        tr('Could not save. Please try again. ({error})',
            {'error': errorText(error)}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _go(_step == _Step.details ? _Step.type : _Step.welcome);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: switch (_step) {
            _Step.welcome => _Welcome(onStart: () => _go(_Step.type)),
            _Step.type => _TypeStep(
                selected: _type,
                onPick: (type) => setState(() => _type = type),
                onBack: () => _go(_Step.welcome),
                onNext: _type == null ? null : () => _go(_Step.details),
              ),
            _Step.details => Form(
                key: _formKey,
                child: _DetailsStep(
                  type: _type!,
                  name: _name,
                  phone: _phone,
                  trades: _trades,
                  onToggle: _toggle,
                  onBack: () => _go(_Step.type),
                ),
              ),
          },
        ),
        bottomNavigationBar: _step == _Step.details
            ? BottomActionBar(
                label: tr('Continue'),
                busy: _saving,
                onPressed: _canSave ? _submit : null,
              )
            : null,
      ),
    );
  }
}

/// A1: language, what the app does, Get started / Restore.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: LanguageToggle(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.engineering_outlined,
                          size: 40, color: AppColors.amberLogo),
                    ),
                    const SizedBox(height: 18),
                    Text(tr('Your work, workers and money in one place'),
                        style: AppText.headlineMedium),
                    const SizedBox(height: 10),
                    Text(
                      tr('Attendance, khata and bills. Works even without internet.'),
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _Feature(
                      icon: Icons.fact_check_outlined,
                      title: tr('Attendance & khata'),
                      text: tr('Mark P / ½ / A, advances and settlements'),
                    ),
                    const SizedBox(height: 18),
                    _Feature(
                      icon: Icons.receipt_long_outlined,
                      title: tr('Bills & quotations'),
                      text: tr('PDF on WhatsApp, track who paid'),
                    ),
                    const SizedBox(height: 18),
                    _Feature(
                      icon: Icons.cloud_done_outlined,
                      title: tr('Your data, your phone'),
                      text: tr('No server. Auto backup to your Google Drive'),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(onPressed: onStart, child: Text(tr('Get started'))),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppSizes.tapSecondary),
                    ),
                    onPressed: () => context.push(Routes.restore),
                    icon: const Icon(Icons.history, size: 20),
                    label: Text(tr('Restore from backup')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.page,
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Icon(icon, size: 22, color: AppColors.ink),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(text,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

/// A2: Contractor / Shopkeeper / Personal.
class _TypeStep extends StatelessWidget {
  const _TypeStep({
    required this.selected,
    required this.onPick,
    required this.onBack,
    required this.onNext,
  });

  final UserType? selected;
  final ValueChanged<UserType> onPick;
  final VoidCallback onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StepHeader(step: 1, total: 3, onBack: onBack),
                  const SizedBox(height: 20),
                  ScreenHeading(
                    tr('Who will use this app?'),
                    subtitle: tr('We set up the tabs and lists for you.'),
                  ),
                  const SizedBox(height: 20),
                  for (final type in UserType.values) ...[
                    UserTypeTile(
                      type: type,
                      selected: selected == type,
                      onTap: () => onPick(type),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    tr('Contractor and Shopkeeper: ₹99/month after a 5-day free trial.'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onNext, child: Text(tr('Continue'))),
            ],
          ),
        ),
      ),
    );
  }
}

/// A3: name, phone and, for a contractor, trades.
class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.type,
    required this.name,
    required this.phone,
    required this.trades,
    required this.onToggle,
    required this.onBack,
  });

  final UserType type;
  final TextEditingController name;
  final TextEditingController phone;
  final Set<Trade> trades;
  final ValueChanged<Trade> onToggle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final personal = type == UserType.personal;
    final (nameLabel, nameHint) = switch (type) {
      UserType.personal => (tr('Your name'), tr('e.g. Priya Sharma')),
      UserType.shop => (tr('Shop name'), tr('e.g. Sharma Cloth House')),
      UserType.contractor => (tr('Business name'), tr('e.g. Sharma Electricals')),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        StepHeader(step: 2, total: 3, onBack: onBack),
        const SizedBox(height: 20),
        ScreenHeading(
          personal ? tr('About you') : tr('About your business'),
          subtitle: personal
              ? tr('Your name is shown on the home screen.')
              : tr('Shown on your bills and pay slips.'),
        ),
        const SizedBox(height: 20),
        FieldLabel(nameLabel),
        TextFormField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: nameHint),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? tr('Enter a name')
              : null,
        ),
        const SizedBox(height: 20),
        FieldLabel(tr('Mobile number'), optional: true),
        TextFormField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: tr('10-digit number'),
            prefixText: '+91 ',
          ),
          validator: (value) => (value == null ||
                  value.trim().isEmpty ||
                  normalizeIndianPhone(value) != null)
              ? null
              : tr('Enter a valid 10-digit mobile number'),
        ),
        if (type.usesTrades) ...[
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(tr('What work do you do?'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              Text(
                tr('{count} selected', {'count': trades.length}),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('Choose one or more. Fills worker roles, units and rate list.'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          TradeGrid(selected: trades, onToggle: onToggle),
        ],
        if (personal) ...[
          const SizedBox(height: 16),
          Text(
            tr('Free for personal use.'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.successText,
            ),
          ),
        ],
      ],
    );
  }
}

/// Two-column grid of trade checkboxes (onboarding A3, Settings S4).
class TradeGrid extends StatelessWidget {
  const TradeGrid({super.key, required this.selected, required this.onToggle});

  final Set<Trade> selected;
  final ValueChanged<Trade> onToggle;

  @override
  Widget build(BuildContext context) {
    final trades = Trade.values;
    return Column(
      children: [
        for (var i = 0; i < trades.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSizes.gap),
          Row(
            children: [
              for (var j = i; j < i + 2; j++) ...[
                if (j > i) const SizedBox(width: AppSizes.gap),
                Expanded(
                  child: j < trades.length
                      ? TradeTile(
                          trade: trades[j],
                          selected: selected.contains(trades[j]),
                          onTap: () => onToggle(trades[j]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Outline used by selectable tiles: blue 2px when on, hairline when off.
ShapeBorder _optionShape(bool selected, double radius) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.border,
        width: selected ? 2 : 1,
      ),
    );

/// One user type: icon, name, description and a radio (wireframe A2).
class UserTypeTile extends StatelessWidget {
  const UserTypeTile({
    super.key,
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final UserType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = _optionShape(selected, AppRadius.tile);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySurface : AppColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.page,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  child: Icon(type.icon,
                      size: 24,
                      color: selected ? Colors.white : AppColors.ink),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              type.label,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (type.isFree) ...[
                            const SizedBox(width: 8),
                            StatusChip(
                              label: tr('FREE'),
                              color: AppColors.successText,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        type.description,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Radio(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.inputBorder,
          width: selected ? 7 : 2,
        ),
      ),
    );
  }
}

/// Selectable trade with a checkbox (onboarding A3, Settings S4).
class TradeTile extends StatelessWidget {
  const TradeTile({
    super.key,
    required this.trade,
    required this.selected,
    required this.onTap,
  });

  final Trade trade;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = _optionShape(selected, AppRadius.input);
    return Semantics(
      checked: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySurface : AppColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : null,
                      borderRadius: BorderRadius.circular(6),
                      border: selected
                          ? null
                          : Border.all(color: AppColors.inputBorder, width: 2),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: AppSizes.gap),
                  Expanded(
                    child: Text(
                      trade.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
