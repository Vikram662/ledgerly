import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../i18n/i18n.dart';

/// Always shown in both languages, so it can be found whichever is on.
const _languageTitle = 'Language / भाषा';

/// Settings row that shows the current language and opens the picker.
class LanguageTile extends StatelessWidget {
  const LanguageTile({super.key, this.closeDrawer = false});

  /// Pops the drawer before the picker opens.
  final bool closeDrawer;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.translate),
      title: const Text(_languageTitle),
      subtitle: Text(appLanguage.value.nativeName),
      trailing: closeDrawer ? null : const Icon(Icons.chevron_right),
      onTap: () {
        final navigator = Navigator.of(context);
        if (closeDrawer) navigator.pop();
        showLanguagePicker(navigator.context);
      },
    );
  }
}

/// Dialog listing every language; the app switches as soon as one is tapped.
Future<void> showLanguagePicker(BuildContext context) async {
  final chosen = await showDialog<AppLanguage>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text(_languageTitle),
      children: [
        for (final language in AppLanguage.values)
          ListTile(
            leading: Icon(
              language == appLanguage.value
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(language.nativeName),
            subtitle: language.nativeName == language.englishName
                ? null
                : Text(language.englishName),
            onTap: () => Navigator.of(context).pop(language),
          ),
      ],
    ),
  );
  if (chosen != null && chosen != appLanguage.value) {
    await setAppLanguage(chosen);
  }
}

/// Compact English | हिंदी pill switch for the first screens (wireframe A1).
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _languageTitle,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.page,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final language in AppLanguage.values)
              _LanguageOption(
                label: language.nativeName,
                selected: language == appLanguage.value,
                onTap: () => setAppLanguage(language),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x1A101828),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.ink : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
