import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/scene_renderer.dart';
import 'package:whiteboard/src/benchmarks/scene_tile_cache.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'tile_cache_test.dart' as helpers;

void main() {
  testWidgets('recovery is opt-in and keeps the original tile footprint', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final recovery in [false, true]) {
        final renderer = await SceneRenderer.create(
          helpers.scene(0),
          cacheTiles: true,
          recoverTiles: recovery,
        );
        try {
          expect(renderer.tileStatistics!['tileSide'], 512);
          await renderer.prepareTiles(Bounds2(0, 0, 600, 128), 1);
          expect(
            renderer.tileStatistics!['bytes'],
            lessThanOrEqualTo(64 * 1024 * 1024),
          );
        } finally {
          renderer.dispose();
        }
      }
      final renderer = await SceneRenderer.create(helpers.scene(0));
      expect(renderer.tileStatistics, isNull);
      renderer.dispose();
    });
  });

  testWidgets('mixed live and cached regions preserve alpha and paint order', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final origin in [0.0, 1e9]) {
        final renderer = await SceneRenderer.create(
          BenchmarkScene([
            BenchmarkNode(
              id: 'under',
              localBounds: Bounds2(0, 0, 40, 100),
              transform: Transform2.translation(origin + 450, origin),
              content: const ShapeContent(ShapeKind.rectangle),
              color: 0xffff0000,
            ),
            BenchmarkNode(
              id: 'over',
              localBounds: Bounds2(450, 50, 690, 50),
              transform: Transform2.translation(origin, origin),
              strokeWidth: 20,
              content: StrokeContent([
                Point2(450, 50),
                Point2(690, 50),
              ], highlighter: true),
            ),
          ]),
          cacheTiles: true,
          recoverTiles: true,
        );
        final view = Bounds2(origin + 450, origin, origin + 706, origin + 128);
        try {
          await renderer.prepareTiles(view, 1);
          // Invalidate one region only, leaving other resident tiles reusable.
          renderer.synchronize(
            renderer.scene.translated('under', Point2(2, 0)),
          );
          final direct = await helpers.pixels(renderer, view, 1, false);
          final mixed = await helpers.pixels(renderer, view, 1, true);
          var error = 0;
          for (var i = 0; i < direct.length; i++) {
            error += (direct[i] - mixed[i]).abs();
          }
          expect(error / direct.length, lessThan(.2));
          expect(renderer.tileStatistics!['mixedPaints'], greaterThan(0));
          await renderer.prepareTiles(view, 1);
        } finally {
          renderer.dispose();
        }
      }
    });
  });

  testWidgets('missing-region callback excludes ready tiles', (tester) async {
    await tester.runAsync(() async {
      final cache = SceneTileCache((bounds, scale) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawPaint(ui.Paint());
        return recorder.endRecording();
      }, recovery: true);
      try {
        await cache.prepare(Bounds2(0, 0, 1536, 100), 1);
        cache.invalidate([Bounds2(20, 20, 30, 30), Bounds2(600, 20, 620, 30)]);
        final missing = <Bounds2>[];
        var callbacks = 0;
        final recorder = ui.PictureRecorder();
        expect(
          cache.paint(
            ui.Canvas(recorder),
            Bounds2(0, 0, 1536, 100),
            1,
            Point2.zero,
            paintMissing: (areas) {
              callbacks++;
              missing.addAll(areas);
            },
          ),
          isTrue,
        );
        recorder.endRecording().dispose();
        expect(missing, hasLength(2));
        expect(callbacks, 1);
        expect(missing.first.right, 512);
        await cache.prepare(Bounds2(0, 0, 1536, 100), 1);
      } finally {
        cache.dispose();
      }
    });
  });

  testWidgets(
    'repeated multi updates preserve index, identity and overlap order',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(
          BenchmarkScene([
            for (var i = 0; i < 4; i++)
              BenchmarkNode(
                id: 'n$i',
                localBounds: Bounds2(0, 0, 20, 20),
                transform: Transform2.translation(i < 2 ? 10 : 1100, 10),
                content: const ShapeContent(ShapeKind.rectangle),
              ),
          ]),
          cacheTiles: true,
          recoverTiles: true,
        );
        try {
          await renderer.prepareTiles(Bounds2(0, 0, 1400, 128), 1);
          final layouts = renderer.textLayoutCount;
          for (var i = 0; i < 100; i++) {
            final current = renderer.scene;
            final next = current.transformed({
              for (final id in ['n0', 'n1'])
                id: Transform2.translation(i.isEven ? 30 : 10, 10),
            });
            renderer.synchronize(next);
            expect(next.delta!.resolvedCount, 2);
            expect(renderer.lastSynchronizedEntries, 2);
            expect(
              identical(next.paintOrder[2], current.paintOrder[2]),
              isTrue,
            );
            expect(renderer.index.query(Bounds2(0, 0, 100, 100)), [0, 1]);
            expect(
              renderer.hitTest(
                Point2(i.isEven ? 35 : 15, 15),
                worldTolerance: 0,
              ),
              'n1',
            );
            expect(renderer.index.query(Bounds2(1000, 0, 1300, 100)), [2, 3]);
            expect(renderer.textLayoutCount, layouts);
          }
          expect(renderer.tileStatistics!['invalidations'], 1);
        } finally {
          renderer.dispose();
        }
      });
    },
  );

  testWidgets('cold recovery close rejects in-flight publication', (
    tester,
  ) async {
    await tester.runAsync(() async {
      late SceneTileCache cache;
      cache = SceneTileCache((bounds, scale) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawPaint(ui.Paint());
        scheduleMicrotask(cache.dispose);
        return recorder.endRecording();
      }, recovery: true);
      await cache.prepare(Bounds2(0, 0, 1000, 600), 1);
      expect(cache.bytes, 0);
      expect(cache.discarded, 1);
      expect(cache.builds, 0);
      cache.dispose();
    });
  });

  testWidgets(
    'zoom reconstruction preserves current geometry after offscreen edits',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(
          helpers.scene(0),
          cacheTiles: true,
          recoverTiles: true,
        );
        try {
          final view = Bounds2(450, 0, 706, 128);
          await renderer.prepareTiles(view, 1);
          final initial = renderer.tileStatistics!['invalidations'];
          renderer.synchronize(renderer.scene.translated('far', Point2(4, 0)));
          expect(renderer.tileStatistics!['invalidations'], initial);
          for (var i = 0; i < 8; i++) {
            await renderer.prepareTiles(
              Bounds2(450, 0, 706, 128),
              .25 * (1 << i),
            );
          }
          await renderer.prepareTiles(view, 1);
          expect(renderer.hitTest(Point2(1115, 15), worldTolerance: 0), 'far');
          expect(
            renderer.tileStatistics!['bytes'],
            lessThanOrEqualTo(64 * 1024 * 1024),
          );
        } finally {
          renderer.dispose();
        }
        expect(renderer.ownedParagraphs, 0);
        expect(renderer.ownedImageHandles, 0);
        expect(renderer.tileStatistics!['bytes'], 0);
      });
    },
  );
  testWidgets(
    'recovery uses ordered direct fallback for fractional text scales',
    (tester) async {
      await tester.runAsync(() async {
        for (final origin in [0.0, 1e9]) {
          final renderer = await SceneRenderer.create(
            BenchmarkScene([
              ...helpers.scene(origin).nodes,
              BenchmarkNode(
                id: 'small',
                localBounds: Bounds2(0, 0, 10, 10),
                transform: Transform2.translation(origin + 450, origin + 10),
                content: const ShapeContent(ShapeKind.rectangle),
              ),
            ]),
            cacheTiles: true,
            recoverTiles: true,
          );
          final view = Bounds2(
            origin + 450,
            origin,
            origin + 706,
            origin + 128,
          );
          try {
            await renderer.prepareTiles(view, 1.25);
            final initialDirect = await helpers.pixels(
              renderer,
              view,
              1.25,
              false,
            );
            final initialCached = await helpers.pixels(
              renderer,
              view,
              1.25,
              true,
            );
            var samplingError = 0;
            for (var i = 0; i < initialDirect.length; i++) {
              samplingError += (initialDirect[i] - initialCached[i]).abs();
            }
            renderer.synchronize(
              renderer.scene.translated('small', Point2(.5, 0)),
            );
            final direct = await helpers.pixels(renderer, view, 1.25, false);
            final mixed = await helpers.pixels(renderer, view, 1.25, true);
            var error = 0;
            for (var i = 0; i < direct.length; i++) {
              error += (direct[i] - mixed[i]).abs();
            }
            // Keep the original composition limit; the reported fallback below
            // additionally requires zero difference from direct glyph AA.
            expect(
              error / direct.length,
              lessThanOrEqualTo(samplingError / direct.length + .25),
            );
            for (final x in [76, 77, 78, 79]) {
              for (final y in [20, 40, 60, 80]) {
                expect(mixed[(y * 256 + x) * 4 + 3], 255);
              }
            }
            int ink(List<int> data) {
              var count = 0;
              for (var i = 0; i < data.length; i += 4) {
                if (data[i] < 50 &&
                    data[i + 1] < 65 &&
                    data[i + 2] < 80 &&
                    data[i + 3] > 128) {
                  count++;
                }
              }
              return count;
            }

            expect(ink(direct), greaterThan(20));
            expect(ink(mixed), closeTo(ink(direct), ink(direct) * .1));
            expect(samplingError, 0);
            expect(error, 0);
            expect(renderer.tileStatistics!['textResamplingFallbacks'], 2);
            expect(renderer.textLayoutCount, 1);
            await renderer.prepareTiles(view, 1.25);
          } finally {
            renderer.dispose();
          }
        }
      });
    },
  );
}
