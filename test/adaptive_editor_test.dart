import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/main.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'support/test_board_store.dart';

Future<void> open(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(WhiteboardApp(store: TestBoardStore()));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(834, 1112),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets('adaptive editor and properties at ${size.width}', (
      tester,
    ) async {
      await open(tester, size);
      expect(tester.takeException(), isNull);
      if (size.width < 700) {
        await tester.tap(find.byTooltip('Tool properties'));
        await tester.pumpAndSettle();
        expect(find.text('Medium'), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.text('Medium'))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More tools'));
        await tester.pumpAndSettle();
        expect(find.text('Insert image'), findsOneWidget);
        expect(find.text('Clear All'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } else {
        expect(find.byTooltip('Shapes'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'two fingers cancel draft and navigate without committing a stroke',
    (tester) async {
      await open(tester, const Size(390, 844));
      final canvas = find.byKey(const ValueKey('board-canvas'));
      final c = tester
          .widget<EditorCanvas>(find.byType(EditorCanvas))
          .controller;
      final origin = tester.getTopLeft(canvas);
      final first = await tester.startGesture(
        origin + const Offset(100, 180),
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      await first.moveTo(origin + const Offset(130, 200));
      final second = await tester.startGesture(
        origin + const Offset(250, 200),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );
      await second.moveTo(origin + const Offset(290, 220));
      await first.moveTo(origin + const Offset(120, 220));
      await second.up();
      await first.moveTo(origin + const Offset(150, 220));
      await first.up();
      await tester.pumpAndSettle();
      expect(c.elementCount, 0);
      expect(c.session.canUndo, false);
      expect(c.camera.zoom, greaterThan(1));
      final draw = await tester.startGesture(
        origin + const Offset(130, 300),
        kind: PointerDeviceKind.touch,
        pointer: 3,
      );
      await draw.moveTo(origin + const Offset(200, 350));
      await draw.up();
      await tester.pumpAndSettle();
      expect(c.elementCount, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'orientation cancels incomplete gesture and keeps committed content',
    (tester) async {
      await open(tester, const Size(390, 844));
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('board-canvas')),
      );
      final c = tester
          .widget<EditorCanvas>(find.byType(EditorCanvas))
          .controller;
      final pointer = await tester.startGesture(
        origin + const Offset(100, 180),
      );
      await pointer.moveTo(origin + const Offset(140, 220));
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      await pointer.up();
      await tester.pumpAndSettle();
      expect(c.elementCount, 0);
      expect(c.hasGesture, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'touch resize handle is a cancel-safe single undoable transform',
    (tester) async {
      await open(tester, const Size(390, 844));
      final c = tester
          .widget<EditorCanvas>(find.byType(EditorCanvas))
          .controller;
      c.session.insert(
        ShapeElementContent(
          kind: ShapeKind.rectangle,
          bounds: Bounds2(0, 0, 100, 80),
          fillColor: 0xff202d46,
        ),
        transform: Transform2.translation(20, 140),
      );
      c.undo();
      c.redo();
      c.setTool(EditorTool.select);
      c.selectedId = c.session.document.elements.single.id;
      await tester.pump();
      final original = c.session.document;
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('board-canvas')),
      );
      var drag = await tester.startGesture(
        origin + const Offset(204, 304),
        kind: PointerDeviceKind.touch,
      );
      await drag.moveTo(origin + const Offset(250, 345));
      await tester.pump();
      expect(c.session.document, same(original));
      await drag.cancel();
      expect(c.session.document, same(original));
      drag = await tester.startGesture(
        origin + const Offset(204, 304),
        kind: PointerDeviceKind.touch,
      );
      await drag.moveTo(origin + const Offset(250, 345));
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.session.document.revision, original.revision + 1);
      expect(c.session.document.elements.single.transform.a, greaterThan(1));
      c.undo();
      expect(
        c.session.document.elements.single.transform,
        original.elements.single.transform,
      );
      c.redo();
      expect(c.session.document.elements.single.transform.a, greaterThan(1));
      expect(
        c.session.document.elements.single.content,
        same(original.elements.single.content),
      );
      final beforeRotation = c.session.document.elements.single.transform;
      final bounds = c.scene
          .boundsOf(c.selectedId!)
          .inflate(c.camera.worldTolerance(4));
      final start = c.camera.worldToViewport(
        Point2(bounds.center.x, bounds.top - c.camera.worldTolerance(24)),
      );
      final end = c.camera.worldToViewport(
        Point2(bounds.center.x + 60, bounds.center.y),
      );
      final rotate = await tester.startGesture(
        origin + Offset(start.x, start.y),
        kind: PointerDeviceKind.mouse,
      );
      await rotate.moveTo(origin + Offset(end.x, end.y));
      await rotate.up();
      await tester.pumpAndSettle();
      expect(
        c.session.document.elements.single.transform.b.abs(),
        greaterThan(.1),
      );
      c.undo();
      expect(c.session.document.elements.single.transform, beforeRotation);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
