import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/i18n/i18n.dart';
import '../../core/security/pin.dart';

/// 4 dots + a 3 × 4 grid of grey keys (PRD AU-02, wireframes A4/A5).
/// Calls [onCompleted] with the PIN once 4 digits are typed.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.error = false,
    this.onBiometric,
  });

  final Future<void> Function(String pin) onCompleted;
  final bool enabled;

  /// Red empty dots after a wrong or rejected PIN.
  final bool error;
  final VoidCallback? onBiometric;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  void clear() => setState(() => _pin = '');

  Future<void> _press(String digit) async {
    if (!widget.enabled || _busy || _pin.length >= pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == pinLength) {
      setState(() => _busy = true);
      try {
        await widget.onCompleted(_pin);
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _pin = '';
          });
        }
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PinDots(count: _pin.length, error: widget.error && _pin.isEmpty),
        const SizedBox(height: 28),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          _row([for (final d in row) _digit(d)]),
        _row([
          widget.onBiometric == null
              ? const SizedBox.shrink()
              : _key(
                  label: tr('Use fingerprint'),
                  color: AppColors.primarySurface,
                  onTap: widget.onBiometric!,
                  child: const Icon(Icons.fingerprint,
                      size: 30, color: AppColors.primary),
                ),
          _digit('0'),
          _key(
            label: tr('Delete'),
            color: Colors.transparent,
            onTap: _backspace,
            child: const Icon(Icons.backspace_outlined,
                size: 26, color: AppColors.ink),
          ),
        ]),
      ],
    );
  }

  Widget _row(List<Widget> keys) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: keys[i]),
            ],
          ],
        ),
      );

  Widget _digit(String digit) => _key(
        label: digit,
        color: AppColors.page,
        onTap: () => _press(digit),
        child: Text(
          digit,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      );

  Widget _key({
    required String label,
    required Color color,
    required VoidCallback onTap,
    required Widget child,
  }) =>
      Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: widget.enabled ? onTap : null,
            child: SizedBox(
              height: AppSizes.pinKey,
              child: Center(child: child),
            ),
          ),
        ),
      );
}

/// Four 18px dots: filled for typed digits, red rings after an error,
/// green when unlocked.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.count,
    this.error = false,
    this.success = false,
  });

  final int count;
  final bool error;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('{count} of {pinLength} digits entered',
          {'count': count, 'pinLength': pinLength}),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < pinLength; i++) ...[
            if (i > 0) const SizedBox(width: 18),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: success
                    ? AppColors.successFill
                    : (i < count ? AppColors.ink : null),
                border: success || i < count
                    ? null
                    : Border.all(
                        color:
                            error ? AppColors.dangerFill : AppColors.inputBorder,
                        width: 2,
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
