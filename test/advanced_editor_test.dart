import 'package:whiteboard/src/persistence/portable_project.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'support/test_board_store.dart';
import 'workspace_widget_test.dart' as workspace;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/editor_page.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'editor_widget_test.dart' as helper;

Future<EditorCanvasController> setup(
  WidgetTester tester, {
  bool mobile = false,
}) async {
  await helper.open(
    tester,
    size: mobile ? const Size(390, 844) : const Size(1200, 850),
  );
  final c = helper.controller(tester);
  c.setTool(EditorTool.rectangle);
  await helper.drag(tester, const Offset(200, 200), const Offset(260, 260));
  await helper.drag(tester, const Offset(400, 200), const Offset(460, 260));
  c.setTool(EditorTool.select);
  return c;
}

Future<void> click(WidgetTester tester, Offset p) async {
  await tester.tapAt(helper.canvasOrigin(tester) + p);
  await tester.pump();
}

void main() {
  testWidgets(
    'Shift toggle, marquee preview and Esc cancellation never commit',
    (tester) async {
      final c = await setup(tester);
      await click(tester, const Offset(200, 230));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await click(tester, const Offset(400, 230));
      expect(c.selectedIds, hasLength(2));
      await click(tester, const Offset(400, 230));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.selectedIds, hasLength(1));
      final document = c.session.document;
      final original = c.selectedIds;
      final gesture = await tester.startGesture(
        helper.canvasOrigin(tester) + const Offset(180, 180),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(
        helper.canvasOrigin(tester) + const Offset(480, 280),
      );
      await tester.pump();
      expect(c.selectedIds, hasLength(2));
      expect(c.marqueeBounds, isNotNull);
      expect(identical(document, c.session.document), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await gesture.up();
      expect(c.selectedIds, original);
      await helper.keyCommand(tester, LogicalKeyboardKey.keyA);
      expect(c.selectedIds, hasLength(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(c.hasSelection, isFalse);
      await click(tester, const Offset(200, 230));
      await click(tester, const Offset(600, 500));
      expect(c.hasSelection, isFalse);
    },
  );

  testWidgets(
    'multi move, resize, rotate and delete each commit once and undo',
    (tester) async {
      final c = await setup(tester);
      c.objectSnapping = false;
      await click(tester, const Offset(200, 230));
      await helper.keyCommand(tester, LogicalKeyboardKey.keyA);
      final original = c.session.document;
      await helper.drag(tester, const Offset(200, 230), const Offset(230, 270));
      expect(c.session.document.revision, original.revision + 1);
      final moved = c.session.document;
      c.undo();
      expect(
        c.session.document.elements.map((e) => e.transform),
        original.elements.map((e) => e.transform),
      );
      c.redo();
      expect(
        c.session.document.elements.map((e) => e.transform),
        moved.elements.map((e) => e.transform),
      );
      final b = c.selectionBounds!;
      final corner = c.camera.worldToViewport(
        Point2(b.right + 4, b.bottom + 4),
      );
      final revision = c.session.document.revision;
      await helper.drag(
        tester,
        Offset(corner.x, corner.y),
        Offset(corner.x + 50, corner.y + 30),
      );
      expect(c.session.document.revision, revision + 1);
      c.rotateSelection();
      expect(c.session.document.revision, revision + 2);
      c.deleteSelection();
      expect(c.elementCount, 0);
      c.undo();
      expect(c.elementCount, 2);
    },
  );

  testWidgets(
    'group selection, internal clipboard and lock discovery use real controls',
    (tester) async {
      final c = await setup(tester);
      await click(tester, const Offset(200, 230));
      await helper.keyCommand(tester, LogicalKeyboardKey.keyA);
      await helper.keyCommand(tester, LogicalKeyboardKey.keyG);
      expect(
        c.session.document.byId[c.selectedId]!.content,
        isA<GroupElementContent>(),
      );
      await click(tester, const Offset(600, 500));
      await click(tester, const Offset(200, 230));
      expect(c.selectedId, isNotNull);
      final revision = c.session.document.revision;
      await c.copySelection();
      await c.pasteSelection();
      expect(c.elementCount, 6);
      expect(c.session.document.revision, revision + 1);
      c.undo();
      expect(c.elementCount, 3);
      await click(tester, const Offset(200, 230));
      c.lockSelection(true);
      expect(c.canEditSelection, isFalse);
      final locked = c.selectedId!;
      c.deleteSelection();
      expect(c.elementCount, 3);
      c.clearAll();
      expect(c.elementCount, 3);
      await tester.tap(find.byTooltip('Selection actions'));
      await tester.pumpAndSettle();
      expect(find.text('Locked items…'), findsOneWidget);
      await tester.tap(find.text('Locked items…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(c.session.document.byId[locked]!.locked, isFalse);
      c.enterGroup();
      await click(tester, const Offset(200, 230));
      expect(
        c.session.document.byId[c.selectedId]!.content,
        isA<ShapeElementContent>(),
      );
      c.exitGroup();
    },
  );

  testWidgets('right click and touch long press expose context actions', (
    tester,
  ) async {
    final c = await setup(tester);
    final gesture = await tester.startGesture(
      helper.canvasOrigin(tester) + const Offset(200, 230),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(c.clipboard.hasContent, isTrue);
    final touch = await tester.startGesture(
      helper.canvasOrigin(tester) + const Offset(400, 230),
    );
    await tester.pump(const Duration(milliseconds: 550));
    await touch.up();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('keyboard shortcuts do not steal focused text input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = EditorCanvasController();
    addTearDown(c.dispose);
    final editor = TextEditingController(text: 'editing');
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: EditorPage(controller: c)),
              TextField(controller: editor),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    c.setTool(EditorTool.rectangle);
    await helper.drag(tester, const Offset(200, 200), const Offset(260, 260));
    c.setTool(EditorTool.select);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final document = c.session.document;
    await helper.keyCommand(tester, LogicalKeyboardKey.keyA);
    await helper.keyCommand(tester, LogicalKeyboardKey.keyX);
    expect(identical(c.session.document, document), isTrue);
  });
  testWidgets(
    'advanced commands autosave and simulated reopening preserve hierarchy, order and locks',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      final c = workspace.canvas(tester);
      c.setTool(EditorTool.rectangle);
      await helper.drag(tester, const Offset(200, 200), const Offset(260, 260));
      await helper.drag(tester, const Offset(400, 200), const Offset(460, 260));
      c.setTool(EditorTool.select);
      c.selectAll();
      c.layoutSelection('top');
      c.groupSelection();
      c.rotateSelection();
      c.duplicateSelection();
      c.reorderSelection('back');
      c.lockSelection(true);
      await tester.pumpAndSettle();
      final expected = DocumentCodec.encode(c.session.document);
      expect(find.text('Saved locally'), findsOneWidget);
      final snapshot = (await store.readBoard(c.session.document.id))!;
      final bytes = await exportPortableProject(snapshot, store);
      expect(
        DocumentCodec.encode(decodePortableProject(bytes).snapshot.document),
        expected,
      );
      await workspace.restart(tester, store);
      final reopened = workspace.canvas(tester);
      expect(DocumentCodec.encode(reopened.session.document), expected);
      expect(reopened.session.canUndo, isFalse);
      expect(
        reopened.session.document.elements.where((e) => e.locked),
        hasLength(1),
      );
      reopened.selectAll();
      expect(reopened.selectedIds, hasLength(1));
      reopened.deleteSelection();
      await tester.pumpAndSettle();
      expect(reopened.elementCount, 3);
      await workspace.restart(tester, store);
      expect(workspace.canvas(tester).elementCount, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('empty group removal refreshes and touch menu fits narrow layout', (
    tester,
  ) async {
    final c = await setup(tester);
    await click(tester, const Offset(200, 230));
    c.selectAll();
    c.groupSelection();
    c.enterGroup();
    c.selectAll();
    c.deleteSelection();
    c.exitGroup();
    c.selectAll();
    // An empty group is not painted; select it explicitly as restored hierarchy UI can.
    c.selectedId = c.session.document.elements.single.id;
    final before = c.session.document.revision;
    c.ungroupSelection();
    expect(c.elementCount, 0);
    expect(c.session.document.revision, before + 1);
    expect(c.hasSelection, isFalse);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    c.setTool(EditorTool.select);
    final touch = await tester.startGesture(
      helper.canvasOrigin(tester) + const Offset(180, 250),
    );
    await tester.pump(const Duration(milliseconds: 550));
    await touch.up();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Touch multi-select'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Touch multi-select'), findsOneWidget);
    await tester.tap(find.text('Touch multi-select'));
    await tester.pumpAndSettle();
    expect(c.multiSelectMode, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'move snapping guides are transient and layout commands use visual bounds',
    (tester) async {
      final c = await setup(tester);
      await click(tester, const Offset(200, 230));
      final before = c.session.document;
      final gesture = await tester.startGesture(
        helper.canvasOrigin(tester) + const Offset(200, 230),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(
        helper.canvasOrigin(tester) + const Offset(397, 230),
      );
      await tester.pump();
      expect(c.snapGuides, isNotEmpty);
      expect(identical(c.session.document, before), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await gesture.up();
      await tester.pump();
      expect(c.snapGuides, isEmpty);
      expect(identical(c.session.document, before), isTrue);
      c.setTool(EditorTool.rectangle);
      await helper.drag(tester, const Offset(600, 330), const Offset(680, 410));
      c.setTool(EditorTool.select);
      c.selectAll();
      c.rotateSelection(.15);
      var revision = c.session.document.revision;
      c.layoutSelection('align-left');
      expect(c.session.document.revision, revision + 1);
      final lefts = c.selectedIds
          .map((id) => c.scene.boundsOf(id).left)
          .toList();
      for (final left in lefts) {
        expect(left, closeTo(lefts.first, 1e-8));
      }
      revision = c.session.document.revision;
      c.layoutSelection('distribute-v');
      expect(c.session.document.revision, revision + 1);
      c.undo();
      expect(c.selectedIds, hasLength(3));
    },
  );
}
