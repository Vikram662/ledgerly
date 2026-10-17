import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/backup/google_drive_auth.dart';
import '../../core/db/meta_store.dart';
import '../../core/db/providers.dart';
import '../../core/i18n/i18n.dart';
import '../../core/security/pin.dart';
import '../../core/widgets/common.dart';
import 'app_lock_controller.dart';
import 'pin_pad.dart';

/// Shown over the whole app while locked or before a PIN exists. Lives in
/// `MaterialApp.builder`, above the router.
///
/// The app ([child], the router's Navigator) is never removed from the tree:
/// it stays mounted under the lock layer, hidden with [Offstage]. Swapping
/// it out and back caused `'_dependents.isEmpty': is not true` assertions
/// (the router's GlobalKey'd Navigator was unmounted mid-transition), and
/// keeping it also returns the user to the same screen after unlocking.
class LockGate extends ConsumerWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider);
    final lock = ref.watch(appLockProvider);

    final Widget? overlay;
    if (profile.isLoading && !profile.hasValue) {
      overlay = const _Splash();
    } else if (profile.valueOrNull == null) {
      // No business yet → onboarding is showing; nothing to protect.
      overlay = null;
    } else {
      overlay = switch (lock.status) {
        LockStatus.unlocked => null,
        LockStatus.checking => const _Splash(),
        LockStatus.needsSetup => const _OwnNavigator(
            key: ValueKey('pin-setup'),
            child: PinSetupScreen(),
          ),
        LockStatus.locked => const _OwnNavigator(
            key: ValueKey('locked'),
            child: LockScreen(),
          ),
      };
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Always first and always present, so its element is never moved.
        Offstage(
          offstage: overlay != null,
          child: TickerMode(enabled: overlay == null, child: child),
        ),
        if (overlay != null) overlay,
      ],
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const BrandSplash();
}

/// The gate sits above the app's router, so lock screens get their own
/// Navigator (for dialogs and overlays).
class _OwnNavigator extends StatelessWidget {
  const _OwnNavigator({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
      );
}

class LockScreen extends ConsumerStatefulWidget {
  /// With [confirmOnly] the screen verifies identity (PRD AU-06) and pops
  /// `true`, without changing the lock state.
  const LockScreen({super.key, this.confirmOnly = false, this.reason});

  final bool confirmOnly;
  final String? reason;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(appLockProvider).lockedUntil != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _done() {
    if (widget.confirmOnly) Navigator.of(context).pop(true);
  }

  Future<void> _tryBiometric() async {
    final lock = ref.read(appLockProvider);
    if (!lock.biometricEnabled) return;
    final ok = await lock.authenticateBiometric(
      reason: widget.reason ?? tr('Unlock Ledgerly'),
      unlock: !widget.confirmOnly,
    );
    if (ok && mounted) _done();
  }

  Future<void> _onPin(String pin) async {
    final result = await ref
        .read(appLockProvider)
        .checkPin(pin, unlock: !widget.confirmOnly);
    if (!mounted) return;
    switch (result) {
      case PinOk():
        setState(() => _error = null);
        _done();
      case PinWrong(:final attemptsLeft):
        setState(() => _error = attemptsLeft > 0
            ? tr('Wrong PIN. {attemptsLeft} tries left.', {'attemptsLeft': attemptsLeft})
            : tr('Wrong PIN.'));
      case PinLockedOut():
        setState(() => _error = tr('Too many wrong tries.'));
    }
  }

  Future<void> _forgotPin() async {
    final email = await MetaStore(ref.read(databaseProvider))
        .get(MetaKeys.driveEmail);
    if (!mounted) return;
    if (email == null) {
      setState(() => _error =
          tr('Google Drive backup is not connected, so the PIN cannot be reset here. Reinstall the app and restore from a backup file.'));
      return;
    }
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _ResetPinSheet(email: email),
    );
    if (go != true || !mounted) return;
    try {
      final verified = await GoogleDriveAuth().verifyAccount();
      if (!mounted) return;
      if (verified.toLowerCase() == email.toLowerCase()) {
        ref.read(appLockProvider).startPinReset();
        if (widget.confirmOnly) Navigator.of(context).pop(false);
      } else {
        setState(() => _error = tr('Please choose the account {email}', {'email': email}));
      }
    } catch (e) {
      if (mounted) setState(() => _error = tr('Google sign-in failed: {e}', {'e': errorText(e)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final until = lock.lockedUntil;
    final waiting = until != null && until.isAfter(DateTime.now());
    final seconds = waiting ? until.difference(DateTime.now()).inSeconds + 1 : 0;

    final name = ref.watch(businessProfileProvider).valueOrNull?.name ?? '';
    final message = waiting
        ? tr('Try again in {seconds} s', {'seconds': seconds})
        : (_error ?? widget.reason ?? tr('Enter your PIN'));
    final isError = waiting || _error != null;

    return PopScope(
      canPop: widget.confirmOnly,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: widget.confirmOnly
            ? AppBar(
                backgroundColor: AppColors.surface,
                title: Text(tr('Confirm it is you')),
              )
            : null,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.gutterWide, 16, AppSizes.gutterWide, 24),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(height: 24),
                    if (!widget.confirmOnly) ...[
                      BrandTile(name: name),
                      const SizedBox(height: 12),
                      Text(
                        tr('Welcome back'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                    ] else
                      const Icon(Icons.lock_outline,
                          size: 48, color: AppColors.primary),
                    const SizedBox(height: 22),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color:
                              isError ? AppColors.dangerText : AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    PinPad(
                      enabled: !waiting,
                      error: isError,
                      onCompleted: _onPin,
                      onBiometric:
                          lock.biometricEnabled && lock.biometricAvailable
                              ? _tryBiometric
                              : null,
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, AppSizes.iconButton),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      onPressed: _forgotPin,
                      child: Text(tr('Forgot PIN?')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains the PIN reset before Google sign-in (wireframe A5).
class _ResetPinSheet extends StatelessWidget {
  const _ResetPinSheet({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Reset your PIN'),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Text(
              tr('Sign in with the Google account your backup uses. Then set a new PIN. Your data stays as it is.'),
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.page,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_circle_outlined,
                      color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(email,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Continue with Google')),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink,
                minimumSize: const Size(0, AppSizes.tapMin),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create a new 4-digit PIN: enter twice, weak PINs rejected (PRD AU-02).
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key, this.popOnDone = false});

  /// True when opened from Settings → Change PIN.
  final bool popOnDone;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String? _first;
  String? _error;

  Future<void> _onPin(String pin) async {
    if (_first == null) {
      if (isWeakPin(pin)) {
        setState(() => _error = tr('This PIN is too easy. Choose another.'));
        return;
      }
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = tr('PINs did not match. Start again.');
      });
      return;
    }
    final lock = ref.read(appLockProvider);
    // Ask before setPin: setting it unlocks the app and removes this screen.
    var enable = false;
    if (lock.biometricAvailable && !lock.biometricEnabled && mounted) {
      enable = await showModalBottomSheet<bool>(
            context: context,
            isDismissible: false,
            builder: (context) => const _FingerprintSheet(),
          ) ??
          false;
    }
    await lock.setPin(pin);
    if (enable) await lock.setBiometricEnabled(true);
    if (widget.popOnDone && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final confirming = _first != null;
    final message = _error ??
        (confirming
            ? tr('Same 4 digits, to confirm.')
            : tr('You will use it to open the app.'));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSizes.gutterWide, 16, AppSizes.gutterWide, 24),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.popOnDone)
                    Row(
                      children: [
                        AppIconButton(
                          icon: Icons.arrow_back,
                          tooltip: tr('Back'),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        const SizedBox(width: 12),
                        Text(tr('Change PIN'),
                            style: AppText.titleLarge),
                      ],
                    )
                  else if (lock.isFirstSetup)
                    const StepHeader(step: 3, total: 3)
                  else
                    const SizedBox(height: 44),
                  const SizedBox(height: 24),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.lock_outline,
                        size: 30, color: AppColors.primary),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    confirming
                        ? tr('Enter the PIN again')
                        : tr('Create a 4-digit PIN'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _error == null
                            ? AppColors.muted
                            : AppColors.dangerText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  PinPad(onCompleted: _onPin, error: _error != null),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "PIN set. Use fingerprint?" (wireframe A4).
class _FingerprintSheet extends StatelessWidget {
  const _FingerprintSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.successSurface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fingerprint,
                    size: 36, color: AppColors.successText),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr('PIN set. Use fingerprint?'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Unlock the app with fingerprint or face. PIN stays as backup.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Use fingerprint')),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink,
                minimumSize: const Size(0, AppSizes.tapMin),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Not now')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for biometric/PIN before sensitive actions (PRD AU-06).
Future<bool> confirmIdentity(BuildContext context, {String? reason}) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LockScreen(confirmOnly: true, reason: reason),
    ),
  );
  return ok ?? false;
}
