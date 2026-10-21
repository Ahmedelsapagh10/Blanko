import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/editor_page.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

EditorCanvasController controller(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).controller;
Offset canvasOrigin(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey('board-canvas')));

Future<void> open(
  WidgetTester tester, {
  Size size = const Size(1200, 850),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: EditorPage()));
  await tester.pump();
}

Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
  final origin = canvasOrigin(tester);
  final gesture = await tester.startGesture(
    origin + from,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(origin + to);
  await gesture.up();
  await tester.pump();
}

Future<void> keyCommand(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets(
    'mouse pen previews independently, commits once and draws visible ink',
    (tester) async {
      await open(tester);
      final c = controller(tester);
      final before = c.session.document;
      final origin = canvasOrigin(tester);
      final gesture = await tester.startGesture(
        origin + const Offset(100, 100),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(origin + const Offset(160, 130));
      await tester.pump();
      expect(identical(c.session.document, before), isTrue);
      expect(c.previewPath, isNotNull);
      await gesture.moveTo(origin + const Offset(220, 100));
      await gesture.up();
      await tester.pump();
      expect(c.session.document.revision, 1);
      expect(c.session.document.elements, hasLength(1));
      expect(
        c.session.document.elements.single.content,
        isA<StrokeElementContent>(),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('board-canvas')),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final index = (115 * image.width + 130) * 4;
          expect(data.getUint8(index), lessThan(80));
          expect(data.getUint8(index + 3), 255);
        } finally {
          image.dispose();
        }
      });
      await tester.tap(find.byTooltip('Undo (⌘/Ctrl Z)'));
      await tester.pump();
      expect(c.session.document.elements, isEmpty);
      await tester.tap(find.byTooltip('Redo (⌘/Ctrl Shift Z)'));
      await tester.pump();
      expect(c.session.document.elements, hasLength(1));
      await keyCommand(tester, LogicalKeyboardKey.keyZ);
      expect(c.session.document.elements, isEmpty);
      await keyCommand(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(c.session.document.elements, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'all basic shape tools commit geometry including backward drags',
    (tester) async {
      await open(tester);
      for (final name in [
        'Rectangle (R)',
        'Ellipse (O)',
        'Triangle (T)',
        'Line (L)',
      ]) {
        await tester.tap(find.byTooltip('Shapes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        await drag(tester, const Offset(320, 250), const Offset(180, 140));
      }
      final elements = controller(tester).session.document.elements;
      expect(elements, hasLength(4));
      expect(
        (elements[0].content as ShapeElementContent).kind,
        ShapeKind.rectangle,
      );
      expect(
        (elements[1].content as ShapeElementContent).kind,
        ShapeKind.ellipse,
      );
      expect(
        (elements[2].content as ShapeElementContent).kind,
        ShapeKind.triangle,
      );
      expect(elements[3].content, isA<LineElementContent>());
      expect(
        (elements[0].content as ShapeElementContent).bounds,
        Bounds2(0, 0, 140, 110),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'select move preview delete and keyboard undo redo use real editor',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Shapes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rectangle (R)'));
      await tester.pumpAndSettle();
      await tester.pump();
      await drag(tester, const Offset(100, 100), const Offset(240, 200));
      final c = controller(tester);
      final id = c.session.document.elements.single.id;
      final before = c.session.document;
      await tester.tap(find.byTooltip('Select (V)'));
      await tester.pump();
      final origin = canvasOrigin(tester);
      final gesture = await tester.startGesture(
        origin + const Offset(100, 145),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(60, 30));
      await tester.pump();
      expect(c.selectedId, id);
      expect(c.moveDelta, Point2(60, 30));
      expect(identical(c.session.document, before), isTrue);
      await gesture.up();
      await tester.pump();
      expect(
        c.session.document.byId[id]!.transform.tx,
        before.byId[id]!.transform.tx + 60,
      );
      expect(c.session.document.revision, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.session.document.elements, isEmpty);
      await keyCommand(tester, LogicalKeyboardKey.keyZ);
      expect(c.session.document.elements.single.id, id);
      await keyCommand(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(c.session.document.elements, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'space pan and zoom controls preserve anchor without authoring elements',
    (tester) async {
      await open(tester);
      final c = controller(tester);
      final translation = c.camera.translation;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await drag(tester, const Offset(100, 100), const Offset(180, 130));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(c.camera.translation, translation + Point2(80, 30));
      expect(c.session.document.elements, isEmpty);
      final anchor = Point2(
        c.viewportSize.width / 2,
        c.viewportSize.height / 2,
      );
      final world = c.camera.viewportToWorld(anchor);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(c.camera.zoom, 1.25);
      expect(
        c.camera.viewportToWorld(anchor).distanceTo(world),
        lessThan(1e-8),
      );
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      expect(c.camera.zoom, 1);
      expect(c.session.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pointer cancel and Escape discard previews without undo entries',
    (tester) async {
      await open(tester);
      final c = controller(tester), origin = canvasOrigin(tester);
      final gesture = await tester.startGesture(
        origin + const Offset(100, 100),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(40, 20));
      await gesture.cancel();
      await tester.pump();
      expect(c.previewPath, isNull);
      final next = await tester.startGesture(
        origin + const Offset(100, 100),
        kind: PointerDeviceKind.mouse,
      );
      await next.moveBy(const Offset(40, 20));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await next.up();
      await tester.pump();
      expect(c.session.document.elements, isEmpty);
      expect(c.session.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'trackpad start clears preview immediately even without an update',
    (tester) async {
      await open(tester);
      final c = controller(tester), origin = canvasOrigin(tester);
      final gesture = await tester.startGesture(
        origin + const Offset(100, 100),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(40, 20));
      var notified = 0;
      c.addListener(() => notified++);
      c.trackpadStart(
        const PointerPanZoomStartEvent(position: Offset(200, 200)),
      );
      expect(notified, 1);
      c.trackpadEnd(const PointerPanZoomEndEvent());
      await gesture.up();
      await tester.pump();
      expect(c.previewPath, isNull);
      expect(c.session.document.elements, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow layout is functional and disposal during drawing is safe',
    (tester) async {
      await open(tester, size: const Size(390, 844));
      expect(
        tester.getSize(find.byKey(const ValueKey('board-canvas'))).height,
        greaterThan(200),
      );
      final gesture = await tester.startGesture(
        canvasOrigin(tester) + const Offset(50, 80),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(40, 20));
      await tester.pumpWidget(const SizedBox());
      await gesture.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
