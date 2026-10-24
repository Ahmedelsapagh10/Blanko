import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource;
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'support/test_board_store.dart';
import 'workspace_widget_test.dart' as workspace;
import 'inline_rich_text_test.dart' as inline;

Future<void> add(WidgetTester tester, EditorTool tool, String text) async {
  await inline.startInlineText(tester, tool: tool);
  await inline.typeInlineText(tester, text);
  await inline.finishInlineText(tester);
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
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('board-canvas')),
      );
      final move = await tester.startGesture(
        origin + const Offset(190, 170),
        kind: PointerDeviceKind.mouse,
      );
      await move.moveTo(origin + const Offset(220, 210));
      await move.up();
      await tester.pumpAndSettle();
      expect(
        c.session.document.elements.single.transform.tx,
        beforeMove.tx + 30,
      );
      expect(
        c.session.document.elements.single.transform.ty,
        beforeMove.ty + 40,
      );
      var text =
          c.session.document.elements.single.content as TextElementContent;
      expect(text.text, 'Hello مرحبا\nWorld العالم');
      expect(c.session.document.fontReferences, hasLength(1));
      c.resizeSelection(
        Bounds2(
          text.bounds.left,
          text.bounds.top,
          text.bounds.left + 160,
          text.bounds.bottom,
        ),
      );
      await tester.pumpAndSettle();
      text = c.session.document.elements.single.content as TextElementContent;
      expect(text.bounds.width, 160);
      c.editSelectedText();
      await tester.pumpAndSettle();
      await inline.typeInlineText(tester, 'Discard me');
      await tester.tap(find.byTooltip('Cancel text editing'));
      await tester.pumpAndSettle();
      expect(
        (c.session.document.elements.single.content as TextElementContent).text,
        text.text,
      );
      c.editSelectedText();
      await tester.pumpAndSettle();
      await inline.typeInlineText(tester, 'مرحبا English\nSecond line');
      final active = inline.draft(tester);
      active.editor.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 25),
        ChangeSource.local,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Font size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('36').last);
      await tester.pumpAndSettle();
      await inline.finishInlineText(tester);
      text = c.session.document.elements.single.content as TextElementContent;
      expect(text.bounds.width, 160);
      expect(
        text.richText!.delta.any(
          (op) => (op['attributes'] as Map?)?['size'] == '36',
        ),
        isTrue,
      );
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
