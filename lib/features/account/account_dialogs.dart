import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/common.dart';

/// Shortest password the server accepts.
const minPasswordLength = 6;

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String value) => _email.hasMatch(value.trim());

/// Validates a password field: at least [minPasswordLength] characters.
String? validatePassword(String? value) =>
    (value ?? '').length < minPasswordLength
        ? tr('Use at least {count} characters', {'count': minPasswordLength})
        : null;

/// Password input with a show / hide eye.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.hint,
    this.validator = validatePassword,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        hintText: widget.hint ?? tr('Password'),
        suffixIcon: IconButton(
          tooltip: _hidden ? tr('Show password') : tr('Hide password'),
          icon: Icon(_hidden
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
      validator: widget.validator,
    );
  }
}

/// What the user typed to log in: email or mobile number, and password.
typedef LoginInput = ({String login, String password});

/// "Log in": email or mobile number + password. Null when cancelled.
Future<LoginInput?> showLoginDialog(BuildContext context) {
  return showDialog<LoginInput>(
    context: context,
    builder: (context) => const _LoginDialog(),
  );
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final text = _login.text.trim();
    Navigator.pop<LoginInput>(context, (
      // A phone number goes as +91…, an email as typed.
      login: text.contains('@') ? text : normalizeIndianPhone(text)!,
      password: _password.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Log in')),
      scrollable: true,
      content: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(tr('Email or mobile number')),
              TextFormField(
                controller: _login,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.telephoneNumber,
                ],
                decoration: InputDecoration(
                    hintText: tr('name@gmail.com or 98765 43210')),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.contains('@')) {
                    return isValidEmail(text)
                        ? null
                        : tr('Enter a valid email address.');
                  }
                  return normalizeIndianPhone(text) != null
                      ? null
                      : tr('Enter your email or 10-digit mobile number');
                },
              ),
              const SizedBox(height: 14),
              FieldLabel(tr('Password')),
              PasswordField(
                controller: _password,
                validator: (value) =>
                    (value ?? '').isEmpty ? tr('Enter your password') : null,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              Text(
                tr('Forgot your password? Contact support with your registered mobile number.'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(tr('Log in'))),
      ],
    );
  }
}

/// A new password (typed twice) and an optional email, for an account that
/// registered without one. Null when cancelled.
Future<({String? email, String password})?> showSetPasswordDialog(
  BuildContext context, {
  String? email,
  required bool hasPhone,
}) {
  return showDialog<({String? email, String password})>(
    context: context,
    builder: (context) => _SetPasswordDialog(email: email, hasPhone: hasPhone),
  );
}

class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog({required this.email, required this.hasPhone});

  final String? email;
  final bool hasPhone;

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email ?? '');
  final _password = TextEditingController();
  final _again = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim();
    Navigator.pop(context, (
      email: email.isEmpty ? null : email.toLowerCase(),
      password: _password.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Set login password')),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Log in on a new phone with your email or mobile number and this password.'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            FieldLabel(tr('Email'), optional: widget.hasPhone),
            TextFormField(
              controller: _email,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(hintText: tr('name@gmail.com')),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) {
                  return widget.hasPhone
                      ? null
                      : tr('Enter an email or a mobile number to log in with.');
                }
                return isValidEmail(text)
                    ? null
                    : tr('Enter a valid email address.');
              },
            ),
            const SizedBox(height: 14),
            FieldLabel(tr('New password')),
            PasswordField(controller: _password),
            const SizedBox(height: 14),
            FieldLabel(tr('Password again')),
            PasswordField(
              controller: _again,
              validator: (value) => value != _password.text
                  ? tr('Passwords do not match')
                  : null,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(tr('Save'))),
      ],
    );
  }
}

/// Asks for this account's password (forgotten PIN). Null when cancelled.
Future<String?> showPasswordCheckDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _PasswordCheckDialog(),
  );
}

class _PasswordCheckDialog extends StatefulWidget {
  const _PasswordCheckDialog();

  @override
  State<_PasswordCheckDialog> createState() => _PasswordCheckDialogState();
}

class _PasswordCheckDialogState extends State<_PasswordCheckDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Reset your PIN')),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Enter your account password. Then set a new PIN. Your data stays as it is.'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: _password,
              autofocus: true,
              validator: (value) =>
                  (value ?? '').isEmpty ? tr('Enter your password') : null,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(tr('Continue'))),
      ],
    );
  }
}
