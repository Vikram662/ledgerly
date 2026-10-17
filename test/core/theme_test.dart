import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/app/theme.dart';
import 'package:thekedaar/core/widgets/common.dart';

void main() {
  test('theme uses the wireframe tokens', () {
    final theme = buildLightTheme();
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.scaffoldBackgroundColor, AppColors.page);
    expect(theme.textTheme.bodyMedium?.fontFamily, AppText.fontFamily);
    expect(theme.textTheme.bodyMedium?.fontFamilyFallback, AppText.fallback);
  });

  test('every font listed in pubspec.yaml is bundled', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = RegExp(r'- asset: (assets/fonts/ui/\S+\.ttf)')
        .allMatches(pubspec)
        .map((m) => m.group(1)!)
        .toList();
    expect(assets, hasLength(8));
    for (final path in assets) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('twoInitials takes the first letters of two words', () {
    expect(twoInitials('Raju Kumar'), 'RK');
    expect(twoInitials('  suresh  '), 'S');
    expect(twoInitials('Mohan Lal Das'), 'ML');
    expect(twoInitials(''), '?');
  });

  testWidgets('primary buttons are blue with white text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: FilledButton(onPressed: () {}, child: const Text('Save')),
      ),
    ));
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, AppColors.primary);
    expect(material.textStyle?.color, Colors.white);
  });
}
