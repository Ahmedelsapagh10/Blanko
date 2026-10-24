import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/inline_text_editor.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'support/test_board_store.dart';
import 'workspace_widget_test.dart' as workspace;

InlineTextDraft draft(WidgetTester tester) =>
    tester.widget<InlineTextLayer>(find.byType(InlineTextLayer)).draft;

Future<void> startInlineText(
  WidgetTester tester, {
  EditorTool tool = EditorTool.text,
}) async {
  workspace.canvas(tester).setTool(tool);
  final origin = tester.getTopLeft(find.byKey(const ValueKey('board-canvas')));
  await tester.tapAt(origin + const Offset(180, 160));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('board-inline-text')), findsOneWidget);
  expect(find.byType(AlertDialog), findsNothing);
}

Future<void> typeInlineText(
  WidgetTester tester,
  String text, {
  TextRange composing = TextRange.empty,
}) async {
  draft(tester).focus.requestFocus();
  await tester.pump();
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: '$text\n',
      selection: TextSelection.collapsed(offset: text.length),
      composing: composing,
    ),
  );
  await tester.pump();
}

Future<void> finishInlineText(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('Done editing'));
  await tester.tap(find.byTooltip('Done editing'));
  await tester.pumpAndSettle();
  expect(find.byType(InlineTextLayer), findsNothing);
}

TextElementContent textContent(WidgetTester tester) =>
    workspace.canvas(tester).session.document.elements.single.content
        as TextElementContent;

void main() {
  testWidgets(
    'inline typing, range formatting and toolbar preserve focus and selection',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      await startInlineText(tester);
      await typeInlineText(tester, 'Hello مرحبا');
      final active = draft(tester);
      active.editor.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
        q.ChangeSource.local,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(
        active.editor.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(active.focus.hasFocus, isTrue);
      await tester.tap(find.byTooltip('Font size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('36').last);
      await tester.pumpAndSettle();
      expect(identical(draft(tester), active), isTrue);
      expect(
        active.editor.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(active.focus.hasFocus, isTrue);
      await tester.tap(find.byTooltip('Font family'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Noto Sans Arabic').last);
      await tester.pumpAndSettle();
      expect(
        active.editor.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(active.focus.hasFocus, isTrue);
      await tester.tap(find.byTooltip('Text color'));
      await tester.pumpAndSettle();
      final color = find
          .descendant(
            of: find.byType(PopupMenuItem<String>),
            matching: find.byType(Text),
          )
          .first;
      final label = tester.widget<Text>(color).data!;
      await tester.tap(color);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Undo text edit'));
      await tester.tap(find.byTooltip('Undo text edit'));
      await tester.pump();
      expect(active.editor.hasRedo, isTrue);
      await tester.ensureVisible(find.byTooltip('Redo text edit'));
      await tester.tap(find.byTooltip('Redo text edit'));
      await tester.pump();
      await finishInlineText(tester);
      final content = textContent(tester);
      expect(content.text, 'Hello مرحبا');
      final first = content.richText!.delta.first;
      expect(first['insert'], 'Hello');
      expect(first['attributes'], containsPair('bold', true));
      expect(first['attributes'], containsPair('size', '36'));
      expect(first['attributes'], containsPair('font', 'Noto Sans Arabic'));
      expect(first['attributes'], containsPair('color', label));
      expect(
        content.richText!.delta
            .skip(1)
            .any((op) => (op['attributes'] as Map?)?['bold'] == true),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'IME composition keeps live controller and draft, then one Board undo',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      await startInlineText(tester);
      final active = draft(tester);
      await typeInlineText(
        tester,
        'مرحبا',
        composing: const TextRange(start: 0, end: 5),
      );
      expect(active.composing, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(identical(draft(tester), active), isTrue);
      expect(active.editor.document.toPlainText(), 'مرحبا\n');
      expect(active.composing, isTrue);
      await typeInlineText(tester, 'مرحبا English');
      await tester.pump(const Duration(milliseconds: 400));
      await typeInlineText(tester, 'مرحبا English\nSecond');
      await tester.pump(const Duration(milliseconds: 400));
      await finishInlineText(tester);
      expect(textContent(tester).text, 'مرحبا English\nSecond');
      final controller = workspace.canvas(tester);
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.elementCount, 0);
      expect(controller.session.canUndo, isFalse);
      controller.redo();
      await tester.pumpAndSettle();
      expect(textContent(tester).text, 'مرحبا English\nSecond');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Escape restores existing content and removes a new empty object',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      await startInlineText(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(workspace.canvas(tester).elementCount, 0);
      await startInlineText(tester);
      await typeInlineText(tester, 'Original');
      await finishInlineText(tester);
      final controller = workspace.canvas(tester);
      controller.editSelectedText();
      await tester.pumpAndSettle();
      await typeInlineText(tester, 'Discarded draft');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(textContent(tester).text, 'Original');
      expect(controller.elementCount, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'acknowledged inline checkpoint reopens with rich text and session-only undo',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await startInlineText(tester);
      final gate = store.writeGate = Completer<void>();
      await typeInlineText(tester, 'Durable مرحبا');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Saved locally'), findsOneWidget);
      expect(
        (await store.readBoard(store.last!))!.document.elements.single.content,
        isA<TextElementContent>().having(
          (e) => e.text,
          'text',
          'Durable مرحبا',
        ),
      );
      await finishInlineText(tester);
      await workspace.restart(tester, store);
      expect(textContent(tester).text, 'Durable مرحبا');
      expect(textContent(tester).richText, isNotNull);
      expect(workspace.canvas(tester).session.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'inline save failure retains content, blocks switch and retries before reopening',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      final id = store.last!;
      await startInlineText(tester);
      store.failWrites = true;
      await typeInlineText(tester, 'Keep this note');
      await finishInlineText(tester);
      expect(find.text('Save failed'), findsOneWidget);
      expect(textContent(tester).text, 'Keep this note');
      await tester.tap(find.byTooltip('Boards'));
      await tester.pumpAndSettle();
      expect(workspace.canvas(tester).session.document.id, id);
      expect(
        find.byKey(const ValueKey('create-board-circle-btn')),
        findsNothing,
      );
      store.failWrites = false;
      await tester.tap(find.byTooltip('Retry save'));
      await tester.pumpAndSettle();
      await workspace.restart(tester, store);
      expect(textContent(tester).text, 'Keep this note');
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'RTL physical alignment translation is reversible without changing text',
    () {
      final original = <Map<String, Object?>>[
        {'insert': 'مرحبا'},
        {
          'insert': '\n',
          'attributes': {'direction': 'rtl', 'align': 'left'},
        },
        {'insert': 'English'},
        {
          'insert': '\n',
          'attributes': {'direction': 'ltr', 'align': 'right'},
        },
        {'insert': 'وسط'},
        {
          'insert': '\n',
          'attributes': {'direction': 'rtl', 'align': 'center'},
        },
      ];
      final editing = quillEditingDelta(original);
      expect((editing[1]['attributes'] as Map)['align'], 'right');
      expect((editing[3]['attributes'] as Map)['align'], 'right');
      expect((editing[5]['attributes'] as Map)['align'], 'center');
      expect(quillEditingDelta(editing), original);
      expect((original[1]['attributes'] as Map)['align'], 'left');
    },
  );

  testWidgets(
    'Arabic automatic direction is outside user history and preserves redo',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      await startInlineText(tester);
      await typeInlineText(tester, 'مرحبا');
      final active = draft(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        active.editor.document.toDelta().toJson().last['attributes'],
        containsPair('direction', 'rtl'),
      );
      active.editor.undo();
      await tester.pump(const Duration(milliseconds: 400));
      expect(active.editor.document.toPlainText(), '\n');
      expect(active.editor.hasRedo, isTrue);
      active.editor.redo();
      await tester.pump(const Duration(milliseconds: 400));
      expect(active.editor.document.toPlainText(), 'مرحبا\n');
      expect(active.editor.hasUndo, isTrue);
      await finishInlineText(tester);
      expect(textContent(tester).text, 'مرحبا');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('undo before first checkpoint clears unsaved draft status', (
    tester,
  ) async {
    await workspace.open(tester, TestBoardStore());
    await startInlineText(tester);
    await typeInlineText(tester, 'Original');
    await finishInlineText(tester);
    final controller = workspace.canvas(tester);
    controller.editSelectedText();
    await tester.pumpAndSettle();
    await typeInlineText(tester, 'Temporary');
    expect(controller.textDraftDirty, isTrue);
    draft(tester).editor.undo();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(draft(tester).editor.document.toPlainText(), 'Original\n');
    expect(controller.textDraftDirty, isFalse);
    expect(find.text('Saving…'), findsNothing);
    expect(find.text('Saved locally'), findsOneWidget);
    await finishInlineText(tester);
    expect(textContent(tester).text, 'Original');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'invalid link stays recoverable and valid replacement finishes normally',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      await startInlineText(tester);
      await typeInlineText(tester, 'Link text');
      final active = draft(tester);
      active.editor.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4),
        q.ChangeSource.local,
      );
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Link'));
      await tester.tap(find.byTooltip('Link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set link'));
      await tester.pumpAndSettle();
      for (final invalid in ['mailto:', 'https://user:password@example.com']) {
        await tester.enterText(find.byType(TextField), invalid);
        await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
        await tester.pumpAndSettle();
        expect(find.text('Text link'), findsOneWidget);
        expect(
          find.text('Use a valid https, http or mailto link.'),
          findsOneWidget,
        );
        expect(identical(draft(tester), active), isTrue);
      }
      await tester.enterText(find.byType(TextField), 'https://example.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Text link'), findsNothing);
      expect(active.error, isNull);
      await finishInlineText(tester);
      expect(
        textContent(tester).richText!.delta.first['attributes'],
        containsPair('link', 'https://example.com'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rotated zoomed inline editor follows world transform and accepts pointer input',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      await startInlineText(tester);
      await typeInlineText(tester, 'Transformed');
      await finishInlineText(tester);
      final controller = workspace.canvas(tester);
      controller.rotateSelection(math.pi / 6);
      controller.zoom(1.5, const Offset(300, 200));
      final element = controller.session.document.elements.single;
      final transform = controller.scene.worldTransformOf(element.id);
      final content = element.content as TextElementContent;
      final expected = controller.camera.worldToViewport(
        transform.apply(Point2(content.bounds.left, content.bounds.top)),
      );
      controller.editSelectedText();
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('board-canvas')),
      );
      final editor = find.byKey(const ValueKey('board-inline-text'));
      final actual = tester.getTopLeft(editor);
      expect(actual.dx, closeTo(origin.dx + expected.x, .01));
      expect(actual.dy, closeTo(origin.dy + expected.y, .01));
      final raw = draft(tester).rawKey.currentState!;
      final caret = raw.renderEditor.getLocalRectForCaret(
        const TextPosition(offset: 3),
      );
      await tester.tapAt(raw.renderEditor.localToGlobal(caret.center));
      await tester.pump();
      expect(find.byType(InlineTextLayer), findsOneWidget);
      await typeInlineText(tester, 'Transformed مرحبا');
      await finishInlineText(tester);
      expect(textContent(tester).text, 'Transformed مرحبا');
      expect(
        controller.session.document.elements.single.transform,
        element.transform,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mobile keyboard inset keeps inline editor and Done action usable',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await startInlineText(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await typeInlineText(tester, 'Mobile مرحبا');
      expect(draft(tester).focus.hasFocus, isTrue);
      await finishInlineText(tester);
      expect(textContent(tester).text, 'Mobile مرحبا');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mobile keyboard reveals a bottom text caret without changing artwork',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final controller = workspace.canvas(tester);
      controller.setTool(EditorTool.text);
      final board = tester.getRect(find.byKey(const ValueKey('board-canvas')));
      await tester.tapAt(Offset(board.left + 40, board.bottom - 120));
      await tester.pumpAndSettle();
      expect(find.byType(InlineTextLayer), findsOneWidget);
      await typeInlineText(tester, 'Bottom note');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final before = controller.session.document.elements.single;
      final cameraBefore = controller.camera.translation;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final active = draft(tester);
      final raw = active.rawKey.currentState!;
      final localCaret = raw.renderEditor.getLocalRectForCaret(
        active.editor.selection.extent,
      );
      final top = raw.renderEditor.localToGlobal(localCaret.topLeft);
      final bottom = raw.renderEditor.localToGlobal(localCaret.bottomRight);
      final visibleBoard = tester.getRect(
        find.byKey(const ValueKey('board-canvas')),
      );
      expect(top.dy, greaterThanOrEqualTo(visibleBoard.top + 72 - 1));
      expect(bottom.dy, lessThanOrEqualTo(visibleBoard.bottom - 20 + 1));
      expect(bottom.dy, lessThanOrEqualTo(844 - 300));
      expect(controller.camera.translation, isNot(cameraBefore));
      final after = controller.session.document.elements.single;
      expect(after.transform, before.transform);
      expect(identical(after.content, before.content), isTrue);
      expect(active.focus.hasFocus, isTrue);
      await finishInlineText(tester);
      expect(textContent(tester).text, 'Bottom note');
      await tester.pumpWidget(const SizedBox());
    },
  );

  // Blanko owns supported shortcuts inside Quill on native and web, so these
  // verify the same text-only dispatch instead of ancestor Focus shortcuts.
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets(
      '${platform.name} select-all and plain paste shortcuts edit the active text',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(SystemChannels.platform, (
            call,
          ) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': 'Pasted مرحبا\r\nSecond'};
            }
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            return null;
          });
          addTearDown(
            () => messenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            ),
          );
          await workspace.open(tester, TestBoardStore());
          await startInlineText(tester);
          await typeInlineText(tester, 'Original مرحبا');
          final active = draft(tester);
          final modifier = platform == TargetPlatform.macOS
              ? LogicalKeyboardKey.metaLeft
              : LogicalKeyboardKey.controlLeft;
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
          await tester.sendKeyUpEvent(modifier);
          await tester.pump();
          expect(active.editor.selection.start, 0);
          expect(
            active.editor.selection.end,
            active.editor.document.length - 1,
          );
          expect(active.focus.hasFocus, isTrue);
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
          await tester.sendKeyUpEvent(modifier);
          await tester.pumpAndSettle();
          expect(identical(draft(tester), active), isTrue);
          expect(
            active.editor.document.toPlainText(),
            'Pasted مرحبا\nSecond\n',
          );
          expect(active.editor.selection.isCollapsed, isTrue);
          await finishInlineText(tester);
          expect(textContent(tester).text, 'Pasted مرحبا\nSecond');
          await tester.pumpWidget(const SizedBox());
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'unsupported rich-text shortcuts cannot add formats and link cancellation keeps draft valid',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      await startInlineText(tester);
      await typeInlineText(tester, 'Safe text');
      final active = draft(tester);
      final before = active.editor.document.toDelta().toJson();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backquote);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(active.editor.document.toDelta().toJson(), before);
      expect(active.error, isNull);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Text link'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(identical(draft(tester), active), isTrue);
      expect(active.error, isNull);
      await finishInlineText(tester);
      expect(textContent(tester).text, 'Safe text');
      expect(
        textContent(tester).richText!.delta
            .expand((op) => ((op['attributes'] as Map?) ?? {}).keys)
            .any(
              (key) =>
                  ['header', 'code-block', 'blockquote', 'link'].contains(key),
            ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mouse tapping translated inline glyphs preserves active draft and keyboard input',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      final controller = workspace.canvas(tester);
      controller.zoom(1.25, const Offset(300, 220));
      controller.setTool(EditorTool.text);
      await tester.pump();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('board-canvas')),
      );
      await tester.tapAt(
        origin + const Offset(400, 300),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await typeInlineText(tester, 'Translated glyphs مرحبا');
      final active = draft(tester);
      final raw = active.rawKey.currentState!;
      final caret = raw.renderEditor.getLocalRectForCaret(
        const TextPosition(offset: 3),
      );
      final point = raw.renderEditor.localToGlobal(caret.center);
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(InlineTextLayer), findsOneWidget);
      expect(identical(draft(tester), active), isTrue);
      expect(active.focus.hasFocus, isTrue);
      final selection = active.editor.selection;
      final text = active.editor.document.toPlainText();
      final next = text.replaceRange(selection.start, selection.end, '!');
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: selection.start + 1),
        ),
      );
      await tester.pump();
      expect(active.editor.document.toPlainText(), next);
      await finishInlineText(tester);
      expect(textContent(tester).text, next.substring(0, next.length - 1));
      controller.editSelectedText();
      await tester.pumpAndSettle();
      final reopened = draft(tester);
      final reopenedRaw = reopened.rawKey.currentState!;
      final reopenedCaret = reopenedRaw.renderEditor.getLocalRectForCaret(
        const TextPosition(offset: 4),
      );
      await tester.tapAt(
        reopenedRaw.renderEditor.localToGlobal(reopenedCaret.center),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.byType(InlineTextLayer), findsOneWidget);
      expect(identical(draft(tester), reopened), isTrue);
      expect(reopened.focus.hasFocus, isTrue);
      await finishInlineText(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mouse double click opens existing text in Select tool', (
    tester,
  ) async {
    await workspace.open(tester, TestBoardStore());
    await startInlineText(tester);
    await typeInlineText(tester, 'Double click to edit');
    await finishInlineText(tester);
    final controller = workspace.canvas(tester);
    controller.setTool(EditorTool.select);
    final element = controller.session.document.elements.single;
    final content = element.content as TextElementContent;
    final world = controller.scene
        .worldTransformOf(element.id)
        .apply(Point2(content.bounds.left + 40, content.bounds.top + 12));
    final screen = controller.camera.worldToViewport(world);
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('board-canvas')),
    );
    final point = origin + Offset(screen.x, screen.y);
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byType(InlineTextLayer), findsOneWidget);
    expect(
      draft(tester).editor.document.toPlainText(),
      'Double click to edit\n',
    );
    expect(controller.elementCount, 1);
    await finishInlineText(tester);
    await tester.pumpWidget(const SizedBox());
  });
}
