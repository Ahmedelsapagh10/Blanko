import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/editor_controls.dart';
import 'package:whiteboard/src/editor/editor_page.dart';
import 'package:whiteboard/src/editor/text_editor_dialog.dart';
import 'package:whiteboard/src/theme/blanko_brand.dart';

Future<EditorCanvasController> _open(
  WidgetTester tester, {
  Size size = const Size(1200, 850),
  double textScale = 1,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = EditorCanvasController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: BlankoTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: EditorPage(controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('tool semantics expose names and current selection', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester);
    final pen = tester.getSemantics(find.byTooltip('Pen (P)'));
    expect(pen.tooltip, 'Pen (P)');
    expect(pen.flagsCollection.isButton, isTrue);
    expect(pen.flagsCollection.isSelected, Tristate.isTrue);
    await tester.tap(find.byTooltip('Select (V)'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byTooltip('Select (V)'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(find.byTooltip('Pen (P)')).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('focused toolbar supports Space activation', (tester) async {
    final c = await _open(tester);
    final selectIcon = find.descendant(
      of: find.byTooltip('Select (V)'),
      matching: find.byType(Icon),
    );
    Focus.of(tester.element(selectIcon)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(c.tool, EditorTool.select);
    expect(c.spaceHeld, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'narrow scaled mobile controls retain touch targets and honor reduced motion',
    (tester) async {
      await _open(
        tester,
        size: const Size(320, 568),
        textScale: 2,
        reducedMotion: true,
      );
      for (final label in [
        'Select (V)',
        'Pen (P)',
        'Object eraser (E)',
        'Shapes',
        'More tools',
        'Tool properties',
      ]) {
        final size = tester.getSize(find.byTooltip(label));
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
      final transitions = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(EditorControls),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(transitions, isNotEmpty);
      expect(transitions.every((w) => w.duration == Duration.zero), isTrue);
      await tester.tap(find.byTooltip('More tools'));
      await tester.pumpAndSettle();
      expect(find.text('Sticky note'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final sticky in [false, true]) {
    testWidgets(
      'dark ${sticky ? 'sticky' : 'text'} draft has legible paper and named touch colors',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: BlankoTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showBoardTextEditor(
                    context,
                    sticky: sticky,
                    color: 0xff202d46,
                  ),
                  child: const Text('Open draft'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open draft'));
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('board-text-input')),
        );
        expect(field.decoration!.filled, isTrue);
        expect(
          field.decoration!.fillColor,
          sticky ? const Color(0xfffff3a3) : Colors.white,
        );
        expect(field.style!.color, const Color(0xff202d46));
        final fontSize = tester.getSemantics(
          find
              .ancestor(
                of: find.byKey(const ValueKey('board-text-font-size')),
                matching: find.byType(MergeSemantics),
              )
              .first,
        );
        final width = tester.getSemantics(
          find
              .ancestor(
                of: find.byKey(const ValueKey('board-text-width')),
                matching: find.byType(MergeSemantics),
              )
              .first,
        );
        expect(fontSize.getSemanticsData().label, contains('Font size'));
        expect(fontSize.getSemanticsData().value, '24 points');
        expect(width.getSemanticsData().label, contains('Text width'));
        expect(
          width.getSemanticsData().value,
          sticky ? '240 pixels' : '320 pixels',
        );
        final paletteButtons = tester.widgetList<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                (widget.tooltip?.startsWith('Ink: ') == true ||
                    widget.tooltip?.startsWith('Paper: ') == true),
          ),
        );
        expect(paletteButtons.length, sticky ? 8 : 4);
        for (final button in paletteButtons) {
          expect(button.tooltip, isNot(matches(RegExp(r'ff[0-9a-f]{6}'))));
          final size = tester.getSize(find.byWidget(button));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('board-text-input')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );
  }
}
