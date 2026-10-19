import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/viewport/camera.dart';
import 'support/test_board_store.dart';
import 'workspace_widget_test.dart' as workspace;

Future<void> erase(
  WidgetTester tester,
  Offset from,
  Offset to, {
  bool cancel = false,
}) async {
  final origin = tester.getTopLeft(find.byKey(const ValueKey('board-canvas')));
  final pointer = await tester.startGesture(
    origin + from,
    kind: PointerDeviceKind.mouse,
  );
  await pointer.moveTo(origin + to);
  if (cancel) {
    await pointer.cancel();
  } else {
    await pointer.up();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'object drag is atomic, cancel safe, zoom aware and durable with undo/redo',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await workspace.pen(tester);
      await workspace.pen(tester, 300);
      await tester.pumpAndSettle();
      final c = workspace.canvas(tester);
      c.setTool(EditorTool.eraser);
      c.setEraserSize(40);
      final revision = c.session.document.revision;
      await erase(
        tester,
        const Offset(150, 130),
        const Offset(350, 130),
        cancel: true,
      );
      expect(c.elementCount, 2);
      expect(c.session.document.revision, revision);
      await erase(tester, const Offset(150, 130), const Offset(350, 130));
      expect(c.elementCount, 0);
      expect(c.session.document.revision, revision + 1);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.elementCount, 2);
      c.redo();
      await tester.pumpAndSettle();
      expect(c.elementCount, 0);
      await workspace.restart(tester, store);
      expect(workspace.canvas(tester).elementCount, 0);
      expect(workspace.canvas(tester).session.canUndo, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'clear cancel, confirm, pending autosave, undo/redo and reopening',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await workspace.pen(tester);
      await tester.pumpAndSettle();
      final c = workspace.canvas(tester),
          id = workspace.canvas(tester).session.document.id;
      await tester.tap(find.byTooltip('Clear All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.elementCount, 1);
      await tester.tap(find.byTooltip('Clear All'));
      await tester.pumpAndSettle();
      final gate = store.writeGate = Completer<void>();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear All'));
      await tester.pumpAndSettle();
      expect(c.elementCount, 0);
      gate.complete();
      await tester.pumpAndSettle();
      c.undo();
      await tester.pumpAndSettle();
      expect(c.elementCount, 1);
      c.redo();
      await tester.pumpAndSettle();
      expect(c.elementCount, 0);
      expect(c.session.document.id, id);
      await workspace.restart(tester, store);
      expect(workspace.canvas(tester).elementCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'segment brush splits stroke without erasing shape, undo restores original',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      final c = workspace.canvas(tester);
      c.session.insert(
        StrokeElementContent(
          points: [Point2(0, 0), Point2(200, 0)],
          style: StrokeStyle(color: 0xff123456, width: 4),
        ),
        transform: Transform2.translation(20, 50),
      );
      // Refresh through undo/redo rather than exposing scene mutation.
      c.session.insert(ShapeElementContent(kind:ShapeKind.rectangle, bounds:Bounds2(0,0,200,100), fillColor:0xff556677),transform:Transform2.translation(20,50));
      c.undo();
      c.redo();
      c.setTool(EditorTool.segmentEraser);
      c.setEraserSize(20);
      await erase(tester, const Offset(200, 110), const Offset(200, 150));
      expect(c.elementCount, 3);
      for (final element in c.session.document.elements.where((e)=>e.content is StrokeElementContent)) {
        expect(
          (element.content as StrokeElementContent).style.color,
          0xff123456,
        );
      }
      c.undo();
      expect(c.elementCount, 2);
      c.redo();
      expect(c.elementCount, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('screen-space size scales into world coordinates at zoom', (
    tester,
  ) async {
    await workspace.open(tester, TestBoardStore());
    final c = workspace.canvas(tester);
    c.session.insert(
      StrokeElementContent(
        points: [Point2(100, 100)],
        style: StrokeStyle(color: 0xff123456, width: 2),
      ),
    );
    c.undo();
    c.redo();
    c.camera = Camera(zoom: 2, translation: Point2.zero);
    c.setTool(EditorTool.eraser);
    c.setEraserSize(8);
    await erase(tester, const Offset(220, 200), const Offset(220, 200));
    expect(c.elementCount, 1);
    c.setEraserSize(48);
    await erase(tester, const Offset(220, 200), const Offset(220, 200));
    expect(c.elementCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
