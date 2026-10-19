import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/benchmark_main.dart';
import 'package:whiteboard/src/benchmarks/benchmark_fixtures.dart';
import 'package:whiteboard/src/benchmarks/benchmark_page.dart';
import 'package:whiteboard/src/benchmarks/benchmark_canvas.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

Future<void> waitForScene(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Synthetic scene did not finish loading.');
}

BenchmarkPainter currentPainter(WidgetTester tester) {
  final layers = find.byType(BenchmarkLayerCanvas);
  if (layers.evaluate().isNotEmpty) {
    return tester.widget<BenchmarkLayerCanvas>(layers).painter;
  }
  return tester
          .widget<CustomPaint>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint && widget.painter is BenchmarkPainter,
            ),
          )
          .painter!
      as BenchmarkPainter;
}

void main() {
  testWidgets('drag commits once; pointer cancellation discards the preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const BenchmarkApp());
    await waitForScene(tester);
    await tester.pump();
    BenchmarkPainter painter() => currentPainter(tester);
    final renderer = painter().renderer;
    final target = renderer.scene.paintOrder.first;
    final viewerFinder = find.byType(InteractiveViewer);
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    final size = tester.getSize(viewerFinder);
    final center = target.worldBounds.center;
    viewer.transformationController!.value = Matrix4.identity()
      ..setEntry(0, 3, size.width / 2 - center.x)
      ..setEntry(1, 3, size.height / 2 - center.y);
    await tester.pump();
    await tester.tap(find.text('Pan mode'));
    await tester.pump();
    final id = renderer.hitTest(center, worldTolerance: 6)!;
    final before = renderer.scene.paintOrder
        .firstWhere((entry) => entry.node.id == id)
        .worldTransform;
    final gesture = await tester.startGesture(
      tester.getCenter(viewerFinder),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(80, 40));
    await tester.pump();
    expect(renderer.revision, 0);
    expect(painter().moveDelta.value, Point2(80, 40));
    await gesture.up();
    await tester.pump();
    expect(renderer.revision, 1);
    final after = renderer.scene.paintOrder
        .firstWhere((entry) => entry.node.id == id)
        .worldTransform;
    expect(
      after
          .apply(Point2.zero)
          .distanceTo(before.apply(Point2.zero) + Point2(80, 40)),
      lessThan(1e-7),
    );
    final cancel = await tester.startGesture(
      tester.getCenter(viewerFinder) + const Offset(80, 40),
      kind: PointerDeviceKind.mouse,
    );
    await cancel.moveBy(const Offset(30, 20));
    await tester.pump();
    await cancel.cancel();
    await tester.pump();
    expect(renderer.revision, 1);
    expect(painter().moveDelta.value, Point2.zero);
    final escape = await tester.startGesture(
      tester.getCenter(viewerFinder) + const Offset(80, 40),
      kind: PointerDeviceKind.mouse,
    );
    await escape.moveBy(const Offset(30, 20));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(painter().moveDelta.value, Point2.zero);
    await escape.up();
    expect(renderer.revision, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'benchmark pans, switches scenes, cancels, and reports current-run timings',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const BenchmarkApp());
      await waitForScene(tester);
      expect(find.textContaining('10,000 drawable elements'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final before = viewer.transformationController!.value.clone();
      viewer.transformationController!.value = Matrix4.identity()
        ..setEntry(0, 0, 0.25)
        ..setEntry(1, 1, 0.25);
      await tester.pump();
      final zoomedPainter = currentPainter(tester);
      expect(zoomedPainter.zoom, 0.25);
      expect(
        zoomedPainter.viewport.width,
        tester.getSize(find.byType(InteractiveViewer)).width * 4,
      );
      viewer.transformationController!.value = before;
      await tester.pump();
      await tester.drag(find.byType(InteractiveViewer), const Offset(100, 50));
      await tester.pumpAndSettle();
      expect(viewer.transformationController!.value, isNot(before));
      await tester.tap(find.text('Dense'));
      await waitForScene(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Run 10 s sweep'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Recording…'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.textContaining('Run cancelled.'), findsOneWidget);
      await tester.tap(find.text('Run 10 s sweep'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final stamp = tester.binding.currentSystemFrameTimeStamp.inMicroseconds;
      ui.FrameTiming timing(int start, int duration) => ui.FrameTiming(
        vsyncStart: start,
        buildStart: start,
        buildFinish: start + duration,
        rasterStart: start + duration,
        rasterFinish: start + duration + 7000,
        rasterFinishWallTime: start + duration + 7000,
      );
      tester.binding.platformDispatcher.onReportTimings!([
        timing(0, 999000),
        timing(stamp, 4000),
      ]);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('1 frames · slower of build/raster: P50 7.00 ms'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone layout remains usable and loading may finish after disposal',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: BenchmarkPage()));
      await waitForScene(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(InteractiveViewer)).height,
        greaterThan(200),
      );
      await tester.tap(find.byType(DropdownButton<SceneDistribution>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Image-heavy').last);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
