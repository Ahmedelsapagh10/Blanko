import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/scene_renderer.dart';
import 'package:whiteboard/src/benchmarks/scene_tile_cache.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'tile_cache_test.dart' as helpers;

void main() {
  testWidgets('dirty tile repair requires both cache and recovery opt-in', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final recovery in [false, true]) {
        for (final repair in [false, true]) {
          final renderer = await SceneRenderer.create(
            helpers.scene(0),
            cacheTiles: true,
            recoverTiles: recovery,
            repairTiles: repair,
          );
          try {
            expect(renderer.tileStatistics!['dirtyRepair'], recovery && repair);
          } finally {
            renderer.dispose();
          }
        }
      }
      final renderer = await SceneRenderer.create(
        helpers.scene(0),
        repairTiles: true,
      );
      expect(renderer.tileStatistics, isNull);
      renderer.dispose();
    });
  });

  testWidgets('repair erases old pixels and preserves translucent source order', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final moved in ['lower', 'upper']) {
        final renderer = await SceneRenderer.create(
          BenchmarkScene([
            BenchmarkNode(
              id: 'lower',
              localBounds: Bounds2(40, 20, 80, 80),
              content: const ShapeContent(ShapeKind.rectangle),
              color: 0xffff0000,
            ),
            BenchmarkNode(
              id: 'upper',
              localBounds: Bounds2(20, 50, 180, 50),
              content: StrokeContent([
                Point2(20, 50),
                Point2(180, 50),
              ], highlighter: true),
              strokeWidth: 20,
              color: 0xff0000ff,
            ),
          ]),
          cacheTiles: true,
          recoverTiles: true,
          repairTiles: true,
        );
        final view = Bounds2(0, 0, 256, 128);
        try {
          await renderer.prepareTiles(view, 1);
          final resident = renderer.tileStatistics!['entries'];
          final originalDirect = await helpers.pixels(renderer, view, 1, false);
          final originalCached = await helpers.pixels(renderer, view, 1, true);
          renderer.synchronize(renderer.scene.translated(moved, Point2(60, 0)));
          expect(renderer.tileStatistics!['entries'], resident);
          expect(renderer.tileStatistics!['dirtyEntries'], greaterThan(0));
          final direct = await helpers.pixels(renderer, view, 1, false);
          final mixed = await helpers.pixels(renderer, view, 1, true);
          await renderer.prepareTiles(view, 1);
          final repaired = await helpers.pixels(renderer, view, 1, true);
          printOnFailure(
            'warm ${_meanError(originalDirect, originalCached)}; '
            'mixed ${_diagnose(direct, mixed)}; repaired ${_diagnose(direct, repaired)}',
          );
          expect(
            _meanError(direct, mixed),
            lessThan(.2),
            reason: 'mixed $moved',
          );
          expect(
            _meanError(direct, repaired),
            lessThan(.2),
            reason: 'repaired $moved',
          );
          final oldPixel = moved == 'lower' ? (45, 25) : (25, 50);
          final oldAlpha = (oldPixel.$2 * 256 + oldPixel.$1) * 4 + 3;
          expect(direct[oldAlpha], 0);
          expect(mixed[oldAlpha], 0);
          expect(repaired[oldAlpha], 0);
          final overlap = (50 * 256 + (moved == 'lower' ? 110 : 75)) * 4;
          for (var channel = 0; channel < 4; channel++) {
            expect(
              repaired[overlap + channel],
              closeTo(direct[overlap + channel], 1),
            );
          }
          expect(renderer.tileStatistics!['repairs'], greaterThan(0));
          expect(renderer.tileStatistics!['dirtyEntries'], 0);
          expect(renderer.tileStatistics!['errors'], 0);
        } finally {
          renderer.dispose();
        }
      }
    });
  });

  testWidgets(
    'local repair replays the damaged region instead of the full tile',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(
          BenchmarkScene([
            BenchmarkNode(
              id: 'edited',
              localBounds: Bounds2(10, 10, 30, 30),
              content: const ShapeContent(ShapeKind.rectangle),
            ),
            for (var i = 0; i < 100; i++)
              BenchmarkNode(
                id: 'unchanged-$i',
                localBounds: Bounds2(0, 0, 12, 12),
                transform: Transform2.translation(
                  180 + (i % 10) * 28.0,
                  180 + (i ~/ 10) * 28.0,
                ),
                content: const ShapeContent(ShapeKind.rectangle),
              ),
          ]),
          cacheTiles: true,
          recoverTiles: true,
          repairTiles: true,
        );
        final view = Bounds2(0, 0, 512, 512);
        try {
          await renderer.prepareTiles(view, 1);
          final fullTileEntries = renderer.index.query(view).length;
          final initialReplayed = renderer.repairReplayedEntries;
          renderer.synchronize(
            renderer.scene.translated('edited', Point2(4, 0)),
          );
          await renderer.prepareTiles(view, 1);
          expect(renderer.lastSynchronizedEntries, 1);
          expect(renderer.tileStatistics!['repairs'], 1);
          expect(
            renderer.repairReplayedEntries - initialReplayed,
            allOf(greaterThan(0), lessThan(fullTileEntries ~/ 10)),
          );
          expect(
            renderer.tileStatistics!['repairPixels'],
            allOf(greaterThan(0), lessThan(512 * 512 ~/ 10)),
          );
          expect(renderer.tileStatistics!['entries'], 1);
          expect(renderer.tileStatistics!['dirtyEntries'], 0);
        } finally {
          renderer.dispose();
        }
      });
    },
  );

  testWidgets(
    'fractional tile fallback retains RTL ink at large world origins',
    (tester) async {
      await tester.runAsync(() async {
        for (final origin in [0.0, 1e9, -1e9]) {
          final renderer = await SceneRenderer.create(
            BenchmarkScene([
              ...helpers.scene(origin).nodes,
              BenchmarkNode(
                id: 'edited',
                localBounds: Bounds2(0, 0, 20, 55),
                transform:
                    Transform2.translation(origin + 502, origin + 20) *
                    Transform2.rotation(.17) *
                    Transform2.scale(1.3, .8),
                content: const ShapeContent(ShapeKind.rectangle),
              ),
            ]),
            cacheTiles: true,
            recoverTiles: true,
            repairTiles: true,
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
            final resamplingError = _meanError(initialDirect, initialCached);
            expect(resamplingError, 0);
            renderer.synchronize(
              renderer.scene.translated('edited', Point2(.5, .25)),
            );
            final direct = await helpers.pixels(renderer, view, 1.25, false);
            final mixed = await helpers.pixels(renderer, view, 1.25, true);
            await renderer.prepareTiles(view, 1.25);
            final repaired = await helpers.pixels(renderer, view, 1.25, true);
            for (final actual in [mixed, repaired]) {
              // Retain the original error bounds and require exact pixels from
              // the reported full-scene fallback, before and after tile repair.
              expect(
                _meanError(direct, actual),
                lessThanOrEqualTo(resamplingError + .3),
              );
              expect(_ink(actual), closeTo(_ink(direct), _ink(direct) * .1));
              expect(_meanError(direct, actual), 0);
              for (final x in [76, 77, 78, 79]) {
                for (final y in [20, 40, 60, 80]) {
                  expect(actual[(y * 256 + x) * 4 + 3], 255);
                }
              }
            }
            expect(_ink(direct), greaterThan(20));
            expect(renderer.textLayoutCount, 1);
            expect(renderer.tileStatistics!['repairs'], greaterThan(0));
            expect(renderer.tileStatistics!['textResamplingFallbacks'], 3);
            expect(renderer.tileStatistics!['paintHits'], 0);
            expect(renderer.lastTileFallbackReason, isNotNull);
            expect(renderer.tileStatistics!['errors'], 0);
          } finally {
            renderer.dispose();
          }
        }
      });
    },
  );

  testWidgets(
    'affected pending repairs retain damage and reject stale pixels',
    (tester) async {
      await tester.runAsync(() async {
        late SceneTileCache cache;
        var revision = 0;
        var invalidatePending = true;
        final seenDamage = <List<Bounds2>>[];
        cache = SceneTileCache(
          (bounds, scale) => _solidPicture(0xff000000 | revision * 40),
          recovery: true,
          repair: (bounds, scale, base, damage) {
            seenDamage.add(List.of(damage));
            final picture = _solidPicture(0xff000000 | revision * 40);
            if (invalidatePending) {
              invalidatePending = false;
              scheduleMicrotask(() {
                revision++;
                cache.invalidate([Bounds2(30, 30, 40, 40)]);
              });
            }
            return picture;
          },
        );
        final view = Bounds2(0, 0, 100, 100);
        try {
          await cache.prepare(view, 1);
          revision++;
          cache.invalidate([Bounds2(5, 5, 10, 10)]);
          await cache.prepare(view, 1);
          expect(cache.discarded, 1);
          expect(cache.repairs, 1);
          expect(seenDamage, hasLength(2));
          expect(seenDamage.last.any((b) => b.contains(Point2(7, 7))), isTrue);
          expect(
            seenDamage.last.any((b) => b.contains(Point2(35, 35))),
            isTrue,
          );
          final pixel = await _cachePixel(cache, view);
          expect(pixel, [0, 0, 80, 255]);
          expect(cache.statistics['dirtyEntries'], 0);
          expect(cache.statistics['pinnedHandles'], 0);
          expect(cache.errors, 0);
        } finally {
          cache.dispose();
        }
      });
    },
  );

  testWidgets('pending repairs respect resident limits and disposal', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final closeDuringRepair in [false, true]) {
        late SceneTileCache cache;
        cache = SceneTileCache(
          (bounds, scale) => _solidPicture(0xff000000),
          byteLimit: SceneTileCache.imageBytes * 2,
          recovery: true,
          repair: (bounds, scale, base, damage) {
            expect(base.width, 514);
            expect(cache.statistics['pinnedHandles'], 1);
            expect(cache.bytes, lessThanOrEqualTo(cache.byteLimit));
            if (closeDuringRepair) scheduleMicrotask(cache.dispose);
            return _solidPicture(0xff0000ff);
          },
        );
        try {
          final view = Bounds2(0, 0, 1024, 100);
          await cache.prepare(view, 1);
          expect(cache.handles, 2);
          cache.invalidate([Bounds2(5, 5, 10, 10)]);
          await cache.prepare(view, 1);
          if (closeDuringRepair) {
            expect(cache.discarded, 1);
            expect(cache.bytes, 0);
          } else {
            expect(cache.repairs, 1);
            expect(cache.handles, 2);
            for (var i = 1; i <= 8; i++) {
              await cache.prepare(
                Bounds2(i * 1024.0, 0, i * 1024.0 + 100, 100),
                1,
              );
              expect(cache.bytes, lessThanOrEqualTo(cache.byteLimit));
            }
            expect(cache.evictions, greaterThan(0));
          }
          expect(cache.statistics['pinnedHandles'], 0);
          expect(cache.errors, 0);
        } finally {
          cache.dispose();
        }
        expect(cache.handles, 0);
        expect(cache.bytes, 0);
        expect(cache.statistics['dirtyEntries'], 0);
        expect(cache.statistics['pinnedHandles'], 0);
      }
    });
  });

  testWidgets(
    'large or fragmented damage falls back to a bounded full rebuild',
    (tester) async {
      await tester.runAsync(() async {
        for (final damage in [
          [Bounds2(0, 0, 512, 512)],
          [
            for (var i = 0; i < 17; i++)
              Bounds2(10 + i * 25.0, 20, 11 + i * 25.0, 21),
          ],
        ]) {
          final cache = SceneTileCache(
            (bounds, scale) => _solidPicture(0xff000000),
            recovery: true,
            repair: (bounds, scale, base, damage) {
              fail('Large or fragmented damage must use a full rebuild.');
            },
          );
          try {
            final view = Bounds2(0, 0, 512, 100);
            await cache.prepare(view, 1);
            cache.invalidate(damage);
            expect(cache.handles, 0);
            expect(cache.statistics['dirtyEntries'], 0);
            await cache.prepare(view, 1);
            expect(cache.builds, 2);
            expect(cache.repairs, 0);
            expect(cache.handles, 1);
            expect(cache.errors, 0);
          } finally {
            cache.dispose();
          }
        }
      });
    },
  );

  testWidgets('failed repair releases its pin and retains a live fallback', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var reject = true;
      var attempts = 0;
      final cache = SceneTileCache(
        (bounds, scale) => _solidPicture(0xff000000),
        recovery: true,
        repair: (bounds, scale, base, damage) {
          attempts++;
          if (reject) throw StateError('Controlled repair failure');
          return _solidPicture(0xff0000ff);
        },
      );
      final view = Bounds2(0, 0, 100, 100);
      try {
        await cache.prepare(view, 1);
        cache.invalidate([Bounds2(5, 5, 10, 10)]);
        await cache.prepare(view, 1);
        expect(cache.errors, 1);
        expect(cache.statistics['pinnedHandles'], 0);
        expect(cache.statistics['dirtyEntries'], 1);
        await cache.prepare(view, 1);
        expect(attempts, 1); // A failed key cannot create a retry loop.
        var callbacks = 0;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        expect(
          cache.paint(
            canvas,
            view,
            1,
            Point2.zero,
            paintMissing: (areas) {
              callbacks++;
              canvas.drawPaint(ui.Paint()..color = const ui.Color(0xff0000ff));
            },
          ),
          isTrue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 16);
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          final inside = (7 * 16 + 7) * 4;
          expect(pixels.sublist(inside, inside + 4), [0, 0, 255, 255]);
          expect(pixels.sublist(0, 4), [0, 0, 0, 255]);
        } finally {
          image.dispose();
          picture.dispose();
        }
        expect(callbacks, 1);
        reject = false;
        cache.invalidate([Bounds2(6, 6, 11, 11)]);
        await cache.prepare(view, 1);
        expect(attempts, 2);
        expect(cache.repairs, 1);
        expect(cache.statistics['dirtyEntries'], 0);
        expect(cache.statistics['pinnedHandles'], 0);
      } finally {
        cache.dispose();
      }
    });
  });
}

double _meanError(Uint8List expected, Uint8List actual) {
  expect(actual.length, expected.length);
  var difference = 0;
  for (var i = 0; i < expected.length; i++) {
    difference += (expected[i] - actual[i]).abs();
  }
  return difference / expected.length;
}

String _diagnose(Uint8List expected, Uint8List actual) {
  var alphaError = 0;
  var transparentError = 0;
  for (var i = 0; i < expected.length; i += 4) {
    alphaError += (expected[i + 3] - actual[i + 3]).abs();
    if (expected[i + 3] == 0 && actual[i + 3] == 0) {
      for (var c = 0; c < 3; c++) {
        transparentError += (expected[i + c] - actual[i + c]).abs();
      }
    }
  }
  final points = [
    for (final p in [(15, 50), (45, 25), (110, 50), (150, 50)])
      '$p: ${expected.sublist((p.$2 * 256 + p.$1) * 4, (p.$2 * 256 + p.$1) * 4 + 4)} / ${actual.sublist((p.$2 * 256 + p.$1) * 4, (p.$2 * 256 + p.$1) * 4 + 4)}',
  ];
  return 'mean=${_meanError(expected, actual)}, alphaError=$alphaError, transparentRGB=$transparentError; $points';
}

int _ink(Uint8List pixels) {
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i] < 50 &&
        pixels[i + 1] < 65 &&
        pixels[i + 2] < 80 &&
        pixels[i + 3] > 128) {
      count++;
    }
  }
  return count;
}

ui.Picture _solidPicture(int color) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawPaint(ui.Paint()..color = ui.Color(color));
  return recorder.endRecording();
}

Future<List<int>> _cachePixel(SceneTileCache cache, Bounds2 view) async {
  final recorder = ui.PictureRecorder();
  expect(cache.paint(ui.Canvas(recorder), view, 1, Point2.zero), isTrue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List().toList();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
