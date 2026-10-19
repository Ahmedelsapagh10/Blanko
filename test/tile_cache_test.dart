import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/scene_renderer.dart';
import 'package:whiteboard/src/benchmarks/scene_tile_cache.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

BenchmarkScene scene(double origin) => BenchmarkScene([
  BenchmarkNode(
    id: 'text',
    localBounds: Bounds2(0, 0, 144, 76),
    transform: Transform2.translation(origin + 480, origin + 10),
    content: const TextContent(
      'فكرة جديدة\nWhiteboard',
      sticky: true,
      rtl: true,
    ),
  ),
  BenchmarkNode(
    id: 'far',
    localBounds: Bounds2(0, 0, 20, 20),
    transform: Transform2.translation(origin + 1100, origin + 10),
    content: const ShapeContent(ShapeKind.rectangle),
  ),
]);

Future<Uint8List> pixels(
  SceneRenderer renderer,
  Bounds2 view,
  double zoom,
  bool cached,
) async {
  final recorder = ui.PictureRecorder();
  renderer.paint(
    ui.Canvas(recorder)..scale(zoom),
    renderer.index.query(view),
    optimized: cached,
    viewport: view,
    zoom: zoom,
    worldOrigin: Point2(view.left, view.top),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 128);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  testWidgets('translucent highlighter stays uniform across a tile seam', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final renderer = await SceneRenderer.create(
        BenchmarkScene([
          BenchmarkNode(
            id: 'highlight',
            localBounds: Bounds2(450, 50, 600, 50),
            strokeWidth: 20,
            color: 0xff2563eb,
            content: StrokeContent([
              Point2(450, 50),
              Point2(600, 50),
            ], highlighter: true),
          ),
        ]),
        cacheTiles: true,
      );
      try {
        final view = Bounds2(450, 0, 706, 128);
        await renderer.prepareTiles(view, 1);
        final direct = await pixels(renderer, view, 1, false);
        final cached = await pixels(renderer, view, 1, true);
        for (final x in [20, 61, 62, 63, 100]) {
          final alpha = (50 * 256 + x) * 4 + 3;
          expect(direct[alpha], inInclusiveRange(70, 72));
          expect(cached[alpha], closeTo(direct[alpha], 1));
        }
      } finally {
        renderer.dispose();
      }
    });
  });

  testWidgets('unrelated mutations do not discard an in-flight tile', (
    tester,
  ) async {
    await tester.runAsync(() async {
      late SceneTileCache cache;
      cache = SceneTileCache((bounds, scale) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawRect(const ui.Rect.fromLTWH(0, 0, 20, 20), ui.Paint());
        scheduleMicrotask(
          () => cache.invalidate([Bounds2(10000, 10000, 10001, 10001)]),
        );
        return recorder.endRecording();
      });
      try {
        await cache.prepare(Bounds2(0, 0, 100, 100), 1);
        expect(cache.builds, 1);
        expect(cache.discarded, 0);
      } finally {
        cache.dispose();
      }
    });
  });

  testWidgets('completed unchanged content survives a camera request change', (
    tester,
  ) async {
    await tester.runAsync(() async {
      late SceneTileCache cache;
      var first = true;
      cache = SceneTileCache((bounds, scale) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawRect(const ui.Rect.fromLTWH(0, 0, 20, 20), ui.Paint());
        if (first) {
          first = false;
          scheduleMicrotask(
            () => unawaited(cache.prepare(Bounds2(600, 0, 700, 100), 1)),
          );
        }
        return recorder.endRecording();
      });
      try {
        await cache.prepare(Bounds2(0, 0, 100, 100), 1);
        expect(cache.builds, 2);
        expect(cache.handles, 2);
        expect(cache.discarded, 0);
      } finally {
        cache.dispose();
      }
    });
  });

  testWidgets(
    'in-flight images are discarded on revision changes or disposal',
    (tester) async {
      await tester.runAsync(() async {
        for (final close in [false, true]) {
          late SceneTileCache cache;
          var first = true;
          cache = SceneTileCache((bounds, scale) {
            final recorder = ui.PictureRecorder();
            ui.Canvas(
              recorder,
            ).drawRect(const ui.Rect.fromLTWH(0, 0, 20, 20), ui.Paint());
            if (first) {
              first = false;
              scheduleMicrotask(() {
                if (close) {
                  cache.dispose();
                } else {
                  cache.invalidate([bounds]);
                }
              });
            }
            return recorder.endRecording();
          });
          try {
            await cache.prepare(Bounds2(0, 0, 100, 100), 1);
            expect(cache.discarded, 1);
            expect(cache.builds, close ? 0 : 1);
            expect(cache.errors, 0);
          } finally {
            cache.dispose();
          }
          expect(cache.bytes, 0);
        }
      });
    },
  );

  testWidgets('raster failure remains bounded and available for live drawing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var attempts = 0;
      final cache = SceneTileCache((bounds, scale) {
        attempts++;
        throw StateError('controlled raster failure');
      });
      try {
        for (var i = 0; i < 5; i++) {
          await cache.prepare(Bounds2(0, 0, 100, 100), 1);
        }
        expect(attempts, 1);
        expect(cache.errors, 1);
        expect(cache.bytes, 0);
      } finally {
        cache.dispose();
      }
    });
  });

  testWidgets('tiles preserve RTL text across seams and large-world origins', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final origin in [0.0, 1e9]) {
        final renderer = await SceneRenderer.create(
          scene(origin),
          cacheTiles: true,
        );
        try {
          final view = Bounds2(
            origin + 450,
            origin,
            origin + 706,
            origin + 128,
          );
          await renderer.prepareTiles(view, 1);
          final direct = await pixels(renderer, view, 1, false);
          final cached = await pixels(renderer, view, 1, true);
          var difference = 0;
          for (var i = 0; i < direct.length; i++) {
            difference += (direct[i] - cached[i]).abs();
          }
          expect(difference / direct.length, lessThan(2));
          int ink(Uint8List pixels) {
            var count = 0;
            for (var i = 0; i < pixels.length; i += 4) {
              if (pixels[i + 3] > 128 &&
                  pixels[i] < 50 &&
                  pixels[i + 1] < 65 &&
                  pixels[i + 2] < 80) {
                count++;
              }
            }
            return count;
          }

          expect(ink(direct), greaterThan(20));
          expect(ink(cached), closeTo(ink(direct), ink(direct) * .1));
          expect(
            renderer.hitTest(
              Point2(origin + 500, origin + 30),
              worldTolerance: 0,
            ),
            'text',
          );
          expect(renderer.textLayoutCount, 1);
          expect(renderer.tileStatistics!['paintHits'], 1);
        } finally {
          renderer.dispose();
        }
      }
    });
  });

  testWidgets(
    'zoom oscillation reuses two buckets without rebuilding text or rasters',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(scene(0), cacheTiles: true);
        final view = Bounds2(450, 0, 650, 120);
        try {
          await renderer.prepareTiles(view, .99);
          await renderer.prepareTiles(view, 1.01);
          final builds = renderer.tileStatistics!['builds'];
          for (var i = 0; i < 100; i++) {
            await renderer.prepareTiles(view, i.isEven ? .99 : 1.01);
          }
          expect(renderer.tileStatistics!['builds'], builds);
          expect(renderer.textLayoutCount, 1);
          expect(
            renderer.tileStatistics!['bytes'],
            lessThanOrEqualTo(64 * 1024 * 1024),
          );
        } finally {
          renderer.dispose();
        }
      });
    },
  );

  testWidgets(
    'single-element changes retain unrelated tiles and stale jobs cannot publish',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(scene(0), cacheTiles: true);
        try {
          await renderer.prepareTiles(Bounds2(0, 0, 1500, 128), 1);
          final initial = renderer.tileStatistics!['entries'] as int;
          renderer.synchronize(renderer.scene.translated('far', Point2(10, 0)));
          expect(renderer.lastSynchronizedEntries, 1);
          expect(renderer.tileStatistics!['entries'], initial - 1);
          final pending = renderer.prepareTiles(Bounds2(1500, 0, 1700, 128), 1);
          renderer.synchronize(renderer.scene.translated('far', Point2(1, 0)));
          renderer.dispose();
          await pending;
          expect(renderer.tileStatistics!['bytes'], 0);
          expect(renderer.ownedImageHandles, 0);
        } finally {
          renderer.dispose();
        }
      });
    },
  );

  testWidgets(
    'LRU is bounded and oversized view requests take the live fallback',
    (tester) async {
      await tester.runAsync(() async {
        final cache = SceneTileCache((bounds, scale) {
          final recorder = ui.PictureRecorder();
          ui.Canvas(
            recorder,
          ).drawRect(const ui.Rect.fromLTWH(0, 0, 20, 20), ui.Paint());
          return recorder.endRecording();
        }, byteLimit: SceneTileCache.imageBytes * 2);
        try {
          for (var i = 0; i < 10; i++) {
            await cache.prepare(Bounds2(i * 512.0, 0, i * 512.0 + 100, 100), 1);
            expect(cache.bytes, lessThanOrEqualTo(cache.byteLimit));
          }
          expect(cache.evictions, 8);
          expect(cache.keysFor(Bounds2(0, 0, 2000, 100), 1), isEmpty);
          expect(cache.keysFor(Bounds2(0, 0, 1, 1), 512), isEmpty);
          expect(SceneTileCache.bucket(.99), 0);
          expect(SceneTileCache.bucket(1.01), 1);
          expect(() => SceneTileCache.bucket(double.nan), throwsArgumentError);
        } finally {
          cache.dispose();
        }
        expect(cache.bytes, 0);
      });
    },
  );
}
