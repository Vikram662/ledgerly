import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/app/theme.dart';
import 'package:thekedaar/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  Future<void> pumpOnboarding(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            home: const OnboardingScreen(),
          ),
        ),
      );

  FilledButton continueButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );

  Future<void> tapVisible(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Lay out the scrolled list before tapping, or the tap lands where the
    // widget was before the jump.
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pump();
  }

  testWidgets('onboarding: a contractor needs a name and a trade',
      (tester) async {
    await pumpOnboarding(tester);
    expect(find.text('Electrical'), findsNothing);
    expect(continueButton(tester).onPressed, isNull);

    await tapVisible(tester, 'Contractor');
    await tester.enterText(find.byType(TextFormField).first, 'Sharma Works');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);

    await tapVisible(tester, 'Plumbing');
    expect(continueButton(tester).onPressed, isNotNull);

    await tapVisible(tester, 'Plumbing');
    expect(continueButton(tester).onPressed, isNull);
  });

  testWidgets('onboarding: personal and shop users need only a name',
      (tester) async {
    await pumpOnboarding(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Priya');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);

    await tapVisible(tester, 'Personal');
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Electrical'), findsNothing);
    expect(continueButton(tester).onPressed, isNotNull);

    await tapVisible(tester, 'Shopkeeper');
    expect(find.text('Shop name'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNotNull);
  });
}
