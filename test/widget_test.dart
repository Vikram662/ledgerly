import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/app/theme.dart';
import 'package:thekedaar/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  Future<void> pumpOnboarding(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const OnboardingScreen(),
        ),
      ),
    );
  }

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

  Future<void> toTypeStep(WidgetTester tester) async {
    await pumpOnboarding(tester);
    expect(find.text('Restore from backup'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pump();
    expect(find.text('Who will use this app?'), findsOneWidget);
  }

  testWidgets('onboarding: a type must be chosen before Continue',
      (tester) async {
    await toTypeStep(tester);
    expect(continueButton(tester).onPressed, isNull);

    await tester.tap(find.text('Personal'));
    await tester.pump();
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('onboarding: a contractor needs a name and a trade',
      (tester) async {
    await toTypeStep(tester);
    await tester.tap(find.text('Contractor'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();

    expect(find.text('About your business'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextFormField).first, 'Sharma Works');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);

    await tapVisible(tester, 'Plumbing');
    expect(continueButton(tester).onPressed, isNotNull);
    expect(find.text('1 selected'), findsOneWidget);

    await tapVisible(tester, 'Plumbing');
    expect(continueButton(tester).onPressed, isNull);
  });

  testWidgets('onboarding: personal and shop users need only a name',
      (tester) async {
    await toTypeStep(tester);
    await tester.tap(find.text('Personal'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();

    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Electrical'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'Priya');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNotNull);

    // Back to the type step keeps the name; switch to a shop.
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.tap(find.text('Shopkeeper'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    expect(find.text('Shop name'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNotNull);
  });
}
