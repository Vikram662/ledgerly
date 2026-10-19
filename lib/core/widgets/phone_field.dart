import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

import '../../app/theme.dart';
import '../i18n/i18n.dart';
import '../utils/phone.dart';
import 'common.dart';

/// Opens the phone's own contact picker (no READ_CONTACTS permission) and
/// returns the chosen name and number, or null if nothing was picked.
Future<({String? name, String phone})?> pickPhoneContact() async {
  final contact = await FlutterNativeContactPicker().selectPhoneNumber();
  final number = contact?.selectedPhoneNumber ??
      ((contact?.phoneNumbers?.isEmpty ?? true)
          ? null
          : contact!.phoneNumbers!.first);
  if (number == null || number.trim().isEmpty) return null;
  final normalized = normalizeIndianPhone(number);
  return (
    name: contact?.fullName?.trim(),
    phone: normalized == null ? number.trim() : formatIndianPhone(normalized),
  );
}

/// The one mobile number field: +91 prefix, Indian number check and a
/// contacts button that fills the number and, when it is empty, [name].
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.name,
    this.hint,
    this.label,
    this.validate = true,
    this.countryCode = true,
  });

  final TextEditingController controller;

  /// Name field filled from the picked contact if still empty.
  final TextEditingController? name;
  final String? hint;

  /// Floating label, for forms that use labels instead of [LabeledField].
  final String? label;
  final bool validate;
  final bool countryCode;

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await pickPhoneContact();
      if (picked == null) return;
      controller.text = picked.phone;
      final pickedName = picked.name;
      if (name != null &&
          name!.text.trim().isEmpty &&
          pickedName != null &&
          pickedName.isNotEmpty) {
        name!.text = pickedName;
      }
    } catch (error) {
      if (context.mounted) {
        showMessage(context, tr('Could not open contacts. ({error})',
            {'error': errorText(error)}));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        hintText: hint ?? (label == null ? tr('10-digit number') : null),
        labelText: label,
        prefixIcon: countryCode ? const PhoneCountryCode() : null,
        suffixIcon: IconButton(
          tooltip: tr('Pick from contacts'),
          icon: const Icon(Icons.contacts_outlined, color: AppColors.primary),
          onPressed: () => _pick(context),
        ),
      ),
      validator: validate
          ? (value) => (value == null ||
                  value.trim().isEmpty ||
                  normalizeIndianPhone(value) != null)
              ? null
              : tr('Enter a valid 10-digit mobile number')
          : null,
    );
  }
}
