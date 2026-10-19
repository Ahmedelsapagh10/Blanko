import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/document/element.dart';
import 'support/test_board_store.dart';
import 'workspace_widget_test.dart' as workspace;

Future<void> add(WidgetTester tester, EditorTool tool, String text) async {
  final c = workspace.canvas(tester);
  c.setTool(tool);
  final origin = tester.getTopLeft(find.byKey(const ValueKey('board-canvas')));
  await tester.tapAt(origin + const Offset(180, 160));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('board-text-input')), text);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'multiline mixed-script text draft cancel, edit/resize, undo, durable reopening',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await add(tester, EditorTool.text, 'Hello مرحبا\nWorld العالم');
      final c = workspace.canvas(tester);
      final beforeMove = c.session.document.elements.single.transform;
      final origin = tester.getTopLeft(find.byKey(const ValueKey('board-canvas')));
      final move = await tester.startGesture(origin + const Offset(190,170), kind:PointerDeviceKind.mouse);
      await move.moveTo(origin + const Offset(220,210)); await move.up(); await tester.pumpAndSettle();
      expect(c.session.document.elements.single.transform.tx, beforeMove.tx+30);
      expect(c.session.document.elements.single.transform.ty, beforeMove.ty+40);
      var text =
          c.session.document.elements.single.content as TextElementContent;
      expect(text.text, 'Hello مرحبا\nWorld العالم');
      expect(c.session.document.fontReferences, hasLength(1));
      c.editSelectedText();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('board-text-input')),
        'Discard me',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (c.session.document.elements.single.content as TextElementContent).text,
        text.text,
      );
      c.editSelectedText();
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('board-text-input'));
      await tester.enterText(field, 'مرحبا English\nSecond line');
      tester.testTextInput.updateEditingValue(const TextEditingValue(text:'مرحبا English\nSecond line',selection:TextSelection.collapsed(offset:5),composing:TextRange(start:0,end:5)));
      expect((c.session.document.elements.single.content as TextElementContent).text,text.text);
      tester
          .widget<Slider>(find.byKey(const ValueKey('board-text-width')))
          .onChanged!(160);
      tester
          .widget<Slider>(find.byKey(const ValueKey('board-text-font-size')))
          .onChanged!(36);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      text = c.session.document.elements.single.content as TextElementContent;
      expect(text.bounds.width, 160);
      expect(text.style.fontSize, 36);
      expect(text.bounds.height, greaterThan(36));
      c.undo();
      await tester.pumpAndSettle();
      expect(
        (c.session.document.elements.single.content as TextElementContent).text,
        'Hello مرحبا\nWorld العالم',
      );
      c.redo();
      await tester.pumpAndSettle();
      await workspace.restart(tester, store);
      expect(
        (workspace.canvas(tester).session.document.elements.single.content
                as TextElementContent)
            .text,
        text.text,
      );
      expect(workspace.canvas(tester).textLayouts, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'sticky note wraps, accepts empty content and persists background through erasing undo',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await add(tester, EditorTool.sticky, 'ملاحظة\nA useful note');
      final c = workspace.canvas(tester);
      final note =
          c.session.document.elements.single.content
              as StickyNoteElementContent;
      expect(note.bounds.height, greaterThanOrEqualTo(120));
      expect(c.textLayouts.values.single.height, greaterThan(0));
      c.deleteSelection();
      await tester.pumpAndSettle();
      expect(c.elementCount, 0);
      c.undo();
      await tester.pumpAndSettle();
      await workspace.restart(tester, store);
      final restored =
          workspace.canvas(tester).session.document.elements.single.content
              as StickyNoteElementContent;
      expect(restored.text, note.text);
      expect(restored.backgroundColor, note.backgroundColor);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
