import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/config.dart';
import '../../../core/db/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/common.dart';
import '../subscription_controller.dart';

Future<bool> requirePro(BuildContext context, WidgetRef ref) async {
  final access = ref.read(subscriptionControllerProvider).valueOrNull;
  if (access?.canWrite == true) return true;
  if (!context.mounted) return false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _PaywallSheet(trialEligible: access?.trialEligible != false),
  );
  return ref.read(subscriptionControllerProvider).valueOrNull?.canWrite == true;
}

class _PaywallSheet extends StatelessWidget {
  const _PaywallSheet({required this.trialEligible});
  final bool trialEligible;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.workspace_premium,
                size: 52, color: AppColors.amber500),
            const SizedBox(height: 12),
            Text(tr('Ledgerly Pro'),
                style: AppText.headlineSmall),
            const SizedBox(height: 8),
            Text(
              trialEligible
                  ? tr('Try it free for 5 days. The mandate is set up today, but the first ₹99 payment is only after 5 days. You can cancel any time during the trial.')
                  : tr('Record sites, attendance, expenses and bills for ₹99/month. You can cancel the subscription any time.'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/settings/subscription');
                },
                child: Text(trialEligible
                    ? tr('Start 5-day free trial')
                    : tr('Subscribe for ₹99/month')),
              ),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Not now'))),
          ]),
        ),
      );
}

class ProRouteGate extends ConsumerWidget {
  const ProRouteGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(subscriptionControllerProvider);
    final access = value.valueOrNull;
    if (access?.canWrite == true) return child;
    if (value.isLoading || access?.kind == AccessKind.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ledgerly Pro required'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.workspace_premium,
                size: 64, color: AppColors.amber500),
            const SizedBox(height: 16),
            Text(tr('Record data with Pro'),
                style: AppText.headlineSmall),
            const SizedBox(height: 8),
            Text(
              access?.trialEligible != false
                  ? tr('Start the 5-day free trial to add or change records. The payment mandate is set up now and the first ₹99 is charged after 5 days.')
                  : tr('Add or change records with the ₹99/month subscription. All view screens remain free.'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.push('/settings/subscription'),
              child: Text(tr('View subscription')),
            ),
            TextButton(
                onPressed: () => context.pop(), child: Text(tr('Back'))),
          ]),
        ),
      ),
    );
  }
}

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  late final Razorpay _razorpay;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _success)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _failure);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(subscriptionControllerProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _subscribe() async {
    if (!AppConfig.subscriptionConfigured) {
      _say(tr('This build is missing SUBSCRIPTION_API_URL.'));
      return;
    }
    setState(() => _opening = true);
    try {
      final profile = await ref.read(businessProfileProvider.future);
      if (profile == null) throw Exception(tr('Complete business setup first.'));
      final controller = ref.read(subscriptionControllerProvider.notifier);
      try {
        await controller.refresh();
        final session = await controller.createCheckout();
        _razorpay.open({
          'key': session.keyId,
          'subscription_id': session.subscriptionId,
          'name': 'Ledgerly Pro',
          'description': '5-day free trial, then ₹99/month',
          'prefill': {'name': profile.name, 'contact': profile.phone ?? ''},
          'theme': {'color': '#B45309'},
          'retry': {'enabled': true, 'max_count': 3},
        });
      } catch (error) {
        await controller.registerProfile(profile);
        final session = await controller.createCheckout();
        _razorpay.open({
          'key': session.keyId,
          'subscription_id': session.subscriptionId,
          'name': 'Ledgerly Pro',
          'description': '5-day free trial, then ₹99/month',
          'prefill': {'name': profile.name, 'contact': profile.phone ?? ''},
          'theme': {'color': '#B45309'},
        });
      }
    } catch (error) {
      _say(errorText(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _success(PaymentSuccessResponse response) async {
    _say(tr('Mandate authorised. Activating your free trial…'));
    await Future<void>.delayed(const Duration(seconds: 2));
    await ref.read(subscriptionControllerProvider.notifier).refresh();
  }

  void _failure(PaymentFailureResponse response) =>
      _say(response.message ?? tr('Payment was not completed.'));

  Future<void> _restore() async {
    final field = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Restore subscription')),
        content: TextField(
          controller: field,
          decoration: InputDecoration(
              labelText: tr('Subscription ID'), hintText: 'sub_xxxxxxxxxx'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: Text(tr('Verify'))),
        ],
      ),
    );
    field.dispose();
    if (id == null || id.trim().isEmpty) return;
    try {
      await ref.read(subscriptionControllerProvider.notifier).link(id);
      _say(tr('Subscription restored.'));
    } catch (error) {
      _say(errorText(error));
    }
  }

  Future<void> _linkGoogle() async {
    try {
      final email =
          await ref.read(subscriptionControllerProvider.notifier).linkGoogle();
      _say(tr('Linked to {email}. Use it to log in on a new phone.',
          {'email': email}));
    } catch (error) {
      _say(errorText(error));
    }
  }

  Future<void> _cancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Cancel subscription?')),
        content: Text(
            tr('Your recurring mandate will be cancelled immediately. If you are still in the 5-day trial, no monthly payment will be charged.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Keep Pro'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Cancel subscription'))),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final result =
          await ref.read(subscriptionControllerProvider.notifier).cancel();
      _say(result['refundStatus'] == null
          ? tr('Subscription cancelled.')
          : tr('Subscription cancelled. Refund: {status}',
              {'status': result['refundStatus']}));
    } catch (error) {
      _say(errorText(error));
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(subscriptionControllerProvider);
    final access = value.valueOrNull;
    final active = access?.canWrite == true;
    final trialEligible = access?.trialEligible != false;
    return Scaffold(
      appBar: AppBar(
        leading: AppIconButton(
          icon: Icons.close,
          tooltip: tr("Close"),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: ref.read(subscriptionControllerProvider.notifier).refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBadge(tr("LEDGERLY PRO"), tone: BadgeTone.pro),
            ),
            const SizedBox(height: 12),
            Text(
              active
                  ? (access?.isTrial == true
                      ? tr("5-day free trial is active")
                      : tr("Pro is active"))
                  : tr("Try 5 days free, then ₹99/month"),
              style: const TextStyle(
                fontSize: 28,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.56,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              active
                  ? tr("You can record all business data.")
                  : tr("Browse the whole app free. Pro lets you add or change records. Cancel any time."),
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 24),
            if (!active) ...[
              _FeatureRow(
                icon: Icons.domain_add_outlined,
                text: tr("Add sites, attendance, bills, expenses"),
              ),
              _FeatureRow(
                icon: Icons.picture_as_pdf_outlined,
                text: tr("Bill and pay slip PDFs on WhatsApp"),
              ),
              _FeatureRow(
                icon: Icons.cloud_off_outlined,
                text: tr("Works offline up to 7 days"),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _PlanCard(
                      title: tr("Free"),
                      price: tr("₹0 forever"),
                      lines: [tr("View every screen and report")],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PlanCard(
                      title: tr("Pro"),
                      price: tr("₹99 / month"),
                      highlighted: true,
                      lines: [tr("View + add + edit records")],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tr("Payment mandate is set up on day 1 via Razorpay. First ₹99 is charged after 5 days; cancel before then to pay nothing."),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ] else ...[
              Panel(
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: AppColors.successText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        access?.isTrial == true
                            ? tr("Your mandate is ready. ₹99 will be charged after the trial unless you cancel first.")
                            : tr("You can record all business data."),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (access != null &&
                AppConfig.driveConfigured &&
                access.kind != AccessKind.setupRequired &&
                access.kind != AccessKind.loading) ...[
              const SizedBox(height: 16),
              _AccountTile(email: access.accountEmail, onLink: _linkGoogle),
            ],
            if (value.isLoading) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
            if (access?.status != null) ...[
              const SizedBox(height: 12),
              Text(
                tr("Status: {status}", {"status": access!.status}),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        label: active
            ? tr("Cancel subscription")
            : trialEligible
                ? tr("Start 5-day free trial")
                : tr("Subscribe · ₹99/month"),
        busy: _opening || value.isLoading,
        onPressed: active ? _cancel : _subscribe,
        bottom: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: active
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (!active)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.ink),
                  onPressed: () => context.pop(),
                  child: Text(tr("Explore free")),
                ),
              TextButton(
                onPressed: _restore,
                child: Text(tr("Restore subscription")),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Google account used to log in again after a reinstall or on a new phone.
class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.email, required this.onLink});

  final String? email;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Icon(email == null ? Icons.link_off : Icons.account_circle_outlined,
              color: email == null ? AppColors.warningText : AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email ?? tr('Google account not linked'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  tr('Log in with it on a new phone to get your plan back.'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (email == null)
            TextButton(onPressed: onLink, child: Text(tr('Link'))),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            IconTile(
              icon,
              color: AppColors.successSurface,
              iconColor: AppColors.successText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.check_circle, color: AppColors.successText, size: 20),
          ],
        ),
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.lines,
    this.highlighted = false,
  });

  final String title;
  final String price;
  final List<String> lines;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.primarySurface : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: highlighted ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.titleMedium),
            const SizedBox(height: 4),
            Text(
              price,
              style: AppText.tabular.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: highlighted ? AppColors.primary : AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            for (final line in lines)
              Text(
                line,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
          ],
        ),
      );
}
