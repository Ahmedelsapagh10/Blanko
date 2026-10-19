import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/theme/blanko_brand.dart';

void main() {
  group('Blanko Brand Tokens and Identity', () {
    test('Tokens match Brand Identity v1.0 specification', () {
      expect(BlankoBrand.appName, 'Blanko');
      expect(BlankoBrand.tagline, 'Where ideas take shape.');
      expect(BlankoBrand.appStoreSubtitle, 'Sketch. Think. Create.');
      expect(
        BlankoBrand.descriptor,
        'Your digital space to think, sketch, and create.',
      );
      expect(BlankoBrand.onboardingHeading, 'Your ideas start here.');
      expect(
        BlankoBrand.onboardingBody,
        'A simple space to think, sketch, and bring ideas to life.',
      );
      expect(
        BlankoBrand.emptyStateHeading,
        'A blank space. Endless possibilities.',
      );
      expect(BlankoBrand.primaryCta, 'Create a board');
      expect(BlankoBrand.defaultBoardTitle, 'Untitled board');

      // Colors
      expect(BlankoBrand.ink, const Color(0xFF15191F));
      expect(BlankoBrand.originBlue, const Color(0xFF4464F6));
      expect(BlankoBrand.canvas, const Color(0xFFFFFFFF));
      expect(BlankoBrand.surface, const Color(0xFFF7F8FA));
      expect(BlankoBrand.border, const Color(0xFFE7EAF0));
      expect(BlankoBrand.mutedText, const Color(0xFF687386));
    });

    test('BlankoTheme light and dark schemes are valid and distinct', () {
      final light = BlankoTheme.light;
      expect(light.brightness, Brightness.light);
      expect(light.colorScheme.primary, BlankoBrand.originBlue);
      expect(light.scaffoldBackgroundColor, BlankoBrand.canvas);
      expect(light.colorScheme.surface, BlankoBrand.surface);

      final dark = BlankoTheme.dark;
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.primary, BlankoBrand.originBlue);
      expect(dark.scaffoldBackgroundColor, BlankoBrand.darkSurface);
      expect(dark.colorScheme.surface, BlankoBrand.darkSurface);
    });

    testWidgets(
      'BlankoSymbol renders vector geometry with accessibility semantics',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: BlankoSymbol(size: 48))),
          ),
        );

        expect(find.byType(BlankoSymbol), findsOneWidget);
        expect(find.bySemanticsLabel('Blanko Logo'), findsOneWidget);
      },
    );

    testWidgets('BlankoWordmark renders vector wordmark with semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: BlankoWordmark(height: 32))),
        ),
      );

      expect(find.byType(BlankoWordmark), findsOneWidget);
      expect(find.bySemanticsLabel('Blanko'), findsOneWidget);
    });
  });
}
