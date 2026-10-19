import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/scene_renderer.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

Future<Uint8List> draw(
  SceneRenderer renderer, {
  bool optimized = false,
  int? moving,
  Point2? origin,
}) async {
  final recorder = ui.PictureRecorder();
  renderer.paint(
    ui.Canvas(recorder),
    [0, 1, 2],
    optimized: optimized,
    movingIndex: moving,
    moveDelta: Point2(3, 4),
    worldOrigin: origin ?? Point2.zero,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 80);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

BenchmarkScene sample(double origin) => BenchmarkScene([
  for (var i = 0; i < 3; i++)
    BenchmarkNode(
      id: 'r$i',
      localBounds: Bounds2(0, 0, 20, 20),
      transform: Transform2.translation(
        origin + 10 + i * 5,
        origin + 10 + i * 5,
      ),
      strokeWidth: 0,
      color: [0xffff0000, 0xff00ff00, 0xff0000ff][i],
      content: const ShapeContent(ShapeKind.rectangle),
    ),
]);
void main() {
  testWidgets(
    'invalid batches are atomic and an older overview cannot publish into a newer revision',
    (tester) async {
      await tester.runAsync(() async {
        final original = sample(0);
        final renderer = await SceneRenderer.create(original);
        try {
          final invalid = original.transformed({
            'r0': Transform2.translation(100, 0),
            'r1': Transform2.translation(1e13, 0),
          });
          expect(() => renderer.synchronize(invalid), throwsArgumentError);
          expect(renderer.scene, same(original));
          expect(renderer.revision, 0);
          expect(renderer.hitTest(Point2(25, 25), worldTolerance: 0), 'r2');
          final pending = renderer.prepareOverview();
          renderer.synchronize(original.translated('r0', Point2(1000, 0)));
          await pending;
          expect(renderer.overviewBytes, 0);
          await renderer.prepareOverview();
          expect(renderer.overviewBytes, greaterThan(0));
          expect(renderer.lastSynchronizedEntries, 1);
        } finally {
          renderer.dispose();
        }
      });
    },
  );

  testWidgets(
    'bounded overview preserves compositing, large origin, full-detail fallback and invalidation',
    (tester) async {
      await tester.runAsync(() async {
        for (final origin in [0.0, 1e9]) {
          final renderer = await SceneRenderer.create(
            sample(origin),
            cacheOverview: true,
          );
          try {
            expect(renderer.overviewBytes, greaterThan(0));
            expect(renderer.overviewBytes, lessThanOrEqualTo(16 * 1024 * 1024));
            final full = await draw(renderer, origin: Point2(origin, origin));
            final cached = await draw(
              renderer,
              optimized: true,
              origin: Point2(origin, origin),
            );
            // Integer bounds and translations make interior compositing exact.
            final pixel = (20 * 80 + 20) * 4;
            expect(
              cached.sublist(pixel, pixel + 4),
              full.sublist(pixel, pixel + 4),
            );
            expect(renderer.lastPaintUsedOverview, isTrue);
            final picture = ui.PictureRecorder();
            renderer.paint(
              ui.Canvas(picture),
              [0, 1, 2],
              optimized: true,
              zoom: 2,
              worldOrigin: Point2(origin, origin),
            );
            picture.endRecording().dispose();
            expect(renderer.lastPaintUsedOverview, isFalse);
            final next = renderer.scene.translated('r0', Point2(100, 0));
            renderer.synchronize(next);
            expect(renderer.lastSynchronizedEntries, 1);
            expect(renderer.overviewBytes, 0);
            expect(
              renderer.hitTest(
                Point2(origin + 115, origin + 15),
                worldTolerance: 0,
              ),
              'r0',
            );
            expect(
              renderer.index.query(
                Bounds2(origin + 110, origin + 10, origin + 120, origin + 20),
              ),
              contains(0),
            );
          } finally {
            renderer.dispose();
          }
          expect(renderer.overviewBytes, 0);
          expect(renderer.ownedParagraphs, 0);
        }
      });
    },
  );
  testWidgets(
    'moving content stays live with correct z-order and no retained preview pictures',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(
          sample(0),
          cacheOverview: true,
        );
        try {
          final full = await draw(renderer, moving: 1);
          final cached = await draw(renderer, optimized: true, moving: 1);
          expect(cached, full);
          expect(renderer.lastPaintUsedOverview, isFalse);
          expect(renderer.ownedParagraphs, 0);
          renderer.synchronize(renderer.scene.translated('r1', Point2(4, 0)));
          expect(renderer.ownedParagraphs, 0);
          // An unrelated, stale branch takes the validated full-scan fallback.
          final independent = sample(0);
          renderer.synchronize(independent);
          expect(renderer.lastSynchronizedEntries, 3);
          expect(renderer.scene, same(independent));
        } finally {
          renderer.dispose();
          renderer.dispose();
        }
      });
    },
  );
  testWidgets(
    'late overview work cannot publish after disposal; sparse scenes allocate no overview',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(sample(0));
        final pending = renderer.prepareOverview();
        expect(identical(pending, renderer.prepareOverview()), isTrue);
        renderer.dispose();
        await pending;
        expect(renderer.overviewBytes, 0);
        final sparse = await SceneRenderer.create(
          BenchmarkScene([
            ...sample(0).nodes,
            BenchmarkNode(
              id: 'far',
              localBounds: Bounds2(0, 0, 10, 10),
              transform: Transform2.translation(1e6, 1e6),
              content: const ShapeContent(ShapeKind.rectangle),
            ),
          ]),
          cacheOverview: true,
        );
        expect(sparse.overviewBytes, 0);
        sparse.dispose();
      });
    },
  );
}
