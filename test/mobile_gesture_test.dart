import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'editor_widget_test.dart' as helper;

void down(
  EditorCanvasController c,
  int id,
  Offset p, [
  PointerDeviceKind kind = PointerDeviceKind.touch,
]) => c.pointerDown(
  PointerDownEvent(
    pointer: id,
    position: p,
    kind: kind,
    buttons: kPrimaryButton,
  ),
);
void move(
  EditorCanvasController c,
  int id,
  Offset p, [
  PointerDeviceKind kind = PointerDeviceKind.touch,
]) => c.pointerMove(
  PointerMoveEvent(
    pointer: id,
    position: p,
    kind: kind,
    buttons: kPrimaryButton,
  ),
);
void up(
  EditorCanvasController c,
  int id,
  Offset p, [
  PointerDeviceKind kind = PointerDeviceKind.touch,
]) => c.pointerUp(PointerUpEvent(pointer: id, position: p, kind: kind));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EditorCanvasController create() {
    final c = EditorCanvasController()..viewportSize = const Size(600, 600);
    addTearDown(c.dispose);
    return c;
  }

  test(
    'second finger cancels ink; focal pan/zoom and staggered lift stay safe',
    () {
      final c = create();
      final document = c.session.document;
      final focalWorld = c.camera.viewportToWorld(Point2(150, 100));
      down(c, 1, const Offset(100, 100));
      move(c, 1, const Offset(120, 110));
      down(c, 2, const Offset(200, 100));
      move(c, 2, const Offset(300, 100));
      // The first finger's current location participates in the actual focal point.
      expect(c.camera.zoom, greaterThan(1));
      expect(c.session.document, same(document));
      expect(c.hasGesture, isFalse);
      up(c, 1, const Offset(120, 110));
      move(c, 2, const Offset(320, 140));
      up(c, 2, const Offset(320, 140));
      expect(c.session.document, same(document));
      expect(focalWorld.x.isFinite, isTrue);
      down(c, 3, const Offset(200, 200));
      move(c, 3, const Offset(240, 220));
      up(c, 3, const Offset(240, 220));
      expect(c.elementCount, 1);
      expect(c.session.document.revision, 1);
      c.undo();
      expect(c.elementCount, 0);
    },
  );

  test('pinch retains world position beneath the moving focal point', () {
    final c = create();
    final world = c.camera.viewportToWorld(Point2(150, 100));
    down(c, 1, const Offset(100, 100));
    down(c, 2, const Offset(200, 100));
    move(c, 2, const Offset(300, 100));
    expect(c.camera.zoom, 2);
    expect(
      c.camera.viewportToWorld(Point2(200, 100)).distanceTo(world),
      lessThan(1e-8),
    );
    up(c, 1, const Offset(100, 100));
    up(c, 2, const Offset(300, 100));
    expect(c.session.canUndo, isFalse);
  });

  test('cancelled third-touch navigation rebases the remaining pair', () {
    final c = create();
    down(c, 1, const Offset(100, 100));
    down(c, 2, const Offset(200, 100));
    down(c, 3, const Offset(300, 100));
    c.pointerCancel(
      const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.touch),
    );
    final zoom = c.camera.zoom;
    move(c, 3, const Offset(400, 100));
    expect(c.camera.zoom, greaterThan(zoom));
    up(c, 2, const Offset(200, 100));
    up(c, 3, const Offset(400, 100));
    expect(c.elementCount, 0);
    down(c, 4, const Offset(100, 200));
    up(c, 4, const Offset(100, 200));
    expect(c.elementCount, 1);
  });

  test(
    'stylus owns its stroke despite finger input and unrelated cancellation',
    () {
      final c = create();
      down(c, 10, const Offset(100, 100), PointerDeviceKind.stylus);
      down(c, 11, const Offset(150, 150));
      down(c, 12, const Offset(200, 150));
      c.pointerCancel(
        const PointerCancelEvent(pointer: 11, kind: PointerDeviceKind.touch),
      );
      move(c, 10, const Offset(240, 200), PointerDeviceKind.stylus);
      up(c, 10, const Offset(240, 200), PointerDeviceKind.stylus);
      up(c, 11, const Offset(150, 150));
      up(c, 12, const Offset(200, 150));
      expect(c.elementCount, 1);
      expect(
        (c.session.document.elements.single.content as StrokeElementContent)
            .points
            .length,
        greaterThan(1),
      );
      expect(c.session.document.revision, 1);
      expect(c.camera.zoom, 1);
    },
  );

  test('unrelated cancellation cannot discard the active finger stroke', () {
    final c = create();
    down(c, 1, const Offset(100, 100));
    c.pointerCancel(
      const PointerCancelEvent(pointer: 99, kind: PointerDeviceKind.mouse),
    );
    expect(c.hasGesture, isTrue);
    move(c, 1, const Offset(200, 150));
    up(c, 1, const Offset(200, 150));
    expect(c.elementCount, 1);
  });

  test('navigation and focus interruption restore pre-marquee selection', () {
    final c = create()..setTool(EditorTool.rectangle);
    for (final x in [150.0, 300.0]) {
      down(c, 1, Offset(x, 150));
      up(c, 1, Offset(x + 50, 200));
    }
    final original = c.session.document.elements.first.id;
    c.setTool(EditorTool.select);
    c.selectedId = original;
    final document = c.session.document;
    down(c, 2, const Offset(100, 100));
    move(c, 2, const Offset(400, 300));
    expect(c.selectedIds, hasLength(2));
    down(c, 3, const Offset(450, 300));
    expect(c.selectedIds, [original]);
    up(c, 2, const Offset(400, 300));
    up(c, 3, const Offset(450, 300));
    down(c, 4, const Offset(100, 100));
    move(c, 4, const Offset(400, 300));
    c.focusLost();
    up(c, 4, const Offset(400, 300));
    expect(c.selectedIds, [original]);
    expect(c.session.document, same(document));
    expect(c.marqueeBounds, isNull);
  });

  testWidgets('backgrounding cancels the draft before a late pointer-up', (
    tester,
  ) async {
    await helper.open(tester);
    final c = helper.controller(tester);
    down(c, 1, const Offset(200, 200));
    move(c, 1, const Offset(250, 250));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(c.hasGesture, isFalse);
    up(c, 1, const Offset(250, 250));
    expect(c.elementCount, 0);
    expect(c.session.canUndo, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  test('touch corner has a 48px target and commits one uniform resize', () {
    final c = create()..setTool(EditorTool.rectangle);
    down(c, 1, const Offset(200, 200));
    up(c, 1, const Offset(300, 300));
    c.setTool(EditorTool.select);
    final id = c.session.document.elements.single.id;
    c.selectedId = id;
    c.objectSnapping = false;
    final before = c.session.document;
    final bounds = c.scene.boundsOf(id);
    down(c, 2, const Offset(326, 304));
    move(c, 2, const Offset(366, 344));
    expect(c.marqueeBounds, isNull);
    expect(c.session.document, same(before));
    up(c, 2, const Offset(366, 344));
    final resized = c.scene.boundsOf(id);
    expect(c.session.document.revision, before.revision + 1);
    expect(resized.width, greaterThan(bounds.width));
    expect(
      resized.width / bounds.width,
      closeTo(resized.height / bounds.height, 1e-8),
    );
    c.undo();
    expect(c.scene.boundsOf(id), bounds);
  });

  testWidgets(
    'viewport resize cancels input and preserves camera without a late commit',
    (tester) async {
      await helper.open(tester);
      final c = helper.controller(tester);
      final camera = c.camera;
      down(c, 1, const Offset(200, 200));
      move(c, 1, const Offset(250, 250));
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      up(c, 1, const Offset(250, 250));
      expect(c.hasGesture, isFalse);
      expect(c.elementCount, 0);
      expect(c.camera.translation, camera.translation);
      expect(c.camera.zoom, camera.zoom);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
