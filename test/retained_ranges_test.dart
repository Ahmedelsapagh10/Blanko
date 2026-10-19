import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/scene_picture_cache.dart';
import 'package:whiteboard/src/benchmarks/scene_renderer.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'tile_cache_test.dart' as helpers;

void main() {
  testWidgets('retained ranges are opt-in and validate active paint indices', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final scene = _overlapScene();
      final direct = await SceneRenderer.create(scene);
      final retained = await SceneRenderer.create(scene, retainRanges: true);
      try {
        expect(direct.retainedStatistics, isNull);
        expect(retained.retainedStatistics!['pictures'], 0);
        expect(
          () => retained.setRetainedActiveIndices([-1]),
          throwsArgumentError,
        );
        expect(
          () => retained.setRetainedActiveIndices([scene.paintOrder.length]),
          throwsArgumentError,
        );
        expect(retained.tileStatistics, isNull);
      } finally {
        direct.dispose();
        retained.dispose();
      }
    });
  });

  testWidgets(
    'interleaved active entries retain alpha and order through preview cancel and commit',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(
          _overlapScene(),
          retainRanges: true,
        );
        final view = Bounds2(0, 0, 256, 128);
        try {
          renderer.setRetainedActiveIndices([1, 3]);
          final baseline = await helpers.pixels(renderer, view, 1, false);
          final warm = await helpers.pixels(renderer, view, 1, true);
          _expectPixels(warm, baseline);
          final builds = renderer.retainedStatistics!['builds'];
          final invalidations = renderer.retainedStatistics!['invalidations'];
          expect(builds, greaterThan(0));
          for (final dx in [12.0, 60.0, -8.0, 0.0]) {
            final direct = await _previewPixels(
              renderer,
              view,
              false,
              movingIndex: 1,
              delta: Point2(dx, 0),
            );
            final retained = await _previewPixels(
              renderer,
              view,
              true,
              movingIndex: 1,
              delta: Point2(dx, 0),
            );
            _expectPixels(retained, direct);
            _expectPixel(retained, direct, 90, 50);
          }
          final cancelled = await helpers.pixels(renderer, view, 1, true);
          _expectPixels(cancelled, baseline);
          expect(renderer.retainedStatistics!['builds'], builds);
          renderer.synchronize(
            renderer.scene.translated('active-blue', Point2(60, 0)),
          );
          renderer.synchronize(
            renderer.scene.translated('active-purple', Point2(-20, 0)),
          );
          final committed = await helpers.pixels(renderer, view, 1, true);
          final committedDirect = await helpers.pixels(
            renderer,
            view,
            1,
            false,
          );
          _expectPixels(committed, committedDirect);
          _expectPixel(committed, committedDirect, 90, 50);
          expect(renderer.retainedStatistics!['builds'], builds);
          expect(renderer.retainedStatistics!['invalidations'], invalidations);
          renderer.setRetainedActiveIndices([]);
          _expectPixels(
            await helpers.pixels(renderer, view, 1, true),
            committedDirect,
          );
          expect(
            renderer.retainedStatistics!['disposedPictures'],
            greaterThan(0),
          );
        } finally {
          renderer.dispose();
        }
      });
    },
  );

  testWidgets(
    'inactive group deltas erase stale pixels and refresh descendants',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(
          BenchmarkScene([
            BenchmarkNode(
              id: 'group',
              localBounds: Bounds2(0, 0, 1, 1),
              content: const GroupContent(),
            ),
            BenchmarkNode(
              id: 'child-red',
              parentId: 'group',
              localBounds: Bounds2(20, 20, 60, 60),
              color: 0xffff0000,
              content: const ShapeContent(ShapeKind.rectangle),
            ),
            BenchmarkNode(
              id: 'child-green',
              parentId: 'group',
              localBounds: Bounds2(60, 25, 75, 55),
              color: 0xff008800,
              content: const ShapeContent(ShapeKind.rectangle),
            ),
            BenchmarkNode(
              id: 'active',
              localBounds: Bounds2(220, 90, 240, 110),
              content: const ShapeContent(ShapeKind.rectangle),
            ),
          ]),
          retainRanges: true,
        );
        final view = Bounds2(0, 0, 256, 128);
        try {
          renderer.setRetainedActiveIndices([2]);
          final before = await helpers.pixels(renderer, view, 1, true);
          expect(before[(35 * 256 + 35) * 4 + 3], greaterThan(0));
          final builds = renderer.retainedStatistics!['builds'] as int;
          await helpers.pixels(renderer, view, 1, false);
          renderer.synchronize(
            renderer.scene.translated('group', Point2(100, 0)),
          );
          expect(renderer.lastSynchronizedEntries, 2);
          expect(renderer.retainedStatistics!['invalidations'], greaterThan(0));
          final direct = await helpers.pixels(renderer, view, 1, false);
          final retained = await helpers.pixels(renderer, view, 1, true);
          _expectPixels(retained, direct);
          expect(direct[(35 * 256 + 35) * 4 + 3], 0);
          expect(retained[(35 * 256 + 35) * 4 + 3], 0);
          _expectPixel(retained, direct, 135, 35);
          expect(renderer.retainedStatistics!['builds'], greaterThan(builds));
          expect(renderer.hitTest(Point2(35, 35), worldTolerance: 0), isNull);
          expect(
            renderer.hitTest(Point2(135, 35), worldTolerance: 0),
            'child-red',
          );
        } finally {
          renderer.dispose();
        }
      });
    },
  );

  testWidgets('camera membership changes never reuse omitted visible entries', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final renderer = await SceneRenderer.create(
        BenchmarkScene([
          for (var i = 0; i < 3; i++)
            BenchmarkNode(
              id: 'shape-$i',
              localBounds: Bounds2(20, 20, 80, 80),
              transform: Transform2.translation(i * 256.0, 0),
              color: [0xffff0000, 0xff008800, 0xff0000ff][i],
              content: const ShapeContent(ShapeKind.rectangle),
            ),
        ]),
        retainRanges: true,
      );
      try {
        for (final x in [0.0, 256.0, 512.0, 0.0]) {
          final view = Bounds2(x, 0, x + 256, 128);
          final direct = await helpers.pixels(renderer, view, 1, false);
          final retained = await helpers.pixels(renderer, view, 1, true);
          _expectPixels(retained, direct);
          expect(retained[(35 * 256 + 35) * 4 + 3], greaterThan(0));
        }
        final builds = renderer.retainedStatistics!['builds'];
        final shifted = Bounds2(1, 0, 257, 128);
        _expectPixels(
          await helpers.pixels(renderer, shifted, 1, true),
          await helpers.pixels(renderer, shifted, 1, false),
        );
        expect(renderer.retainedStatistics!['builds'], builds);
        expect(renderer.retainedStatistics!['reuses'], greaterThan(0));
        expect(
          renderer.retainedStatistics!['disposedPictures'],
          greaterThan(0),
        );
      } finally {
        renderer.dispose();
      }
    });
  });

  testWidgets(
    'fractional vector reuse preserves RTL images and large world origins',
    (tester) async {
      await tester.runAsync(() async {
        for (final origin in [0.0, 1e9, -1e9]) {
          final renderer = await SceneRenderer.create(
            _richScene(origin),
            retainRanges: true,
            imageSide: 64,
          );
          final view = Bounds2(origin, origin, origin + 204.8, origin + 102.4);
          try {
            final direct = await helpers.pixels(renderer, view, 1.25, false);
            final retained = await helpers.pixels(renderer, view, 1.25, true);
            _expectPixels(retained, direct);
            final builds = renderer.retainedStatistics!['builds'];
            _expectPixels(
              await helpers.pixels(renderer, view, 1.25, true),
              direct,
            );
            expect(renderer.retainedStatistics!['builds'], builds);
            expect(_ink(direct), greaterThan(20));
            expect(_ink(retained), _ink(direct));
            expect(retained[(50 * 256 + 210) * 4 + 3], 255);
            expect(renderer.imageBytes, 64 * 64 * 4);
            expect(renderer.textLayoutCount, 1);
            renderer.synchronize(
              renderer.scene.translated('image', Point2(.5, 0)),
            );
            _expectPixels(
              await helpers.pixels(renderer, view, 1.25, true),
              await helpers.pixels(renderer, view, 1.25, false),
            );
          } finally {
            renderer.dispose();
          }
          expect(renderer.ownedImageHandles, 0);
          expect(renderer.ownedParagraphs, 0);
          expect(renderer.retainedStatistics!['pictures'], 0);
          expect(renderer.retainedStatistics!['approximateBytes'], 0);
        }
      });
    },
  );

  testWidgets('omitted text or images bypass full-content retained pictures', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final renderer = await SceneRenderer.create(
        _richScene(0),
        retainRanges: true,
        imageSide: 32,
      );
      final view = Bounds2(0, 0, 256, 128);
      try {
        await helpers.pixels(renderer, view, 1, true);
        final builds = renderer.retainedStatistics!['builds'];
        for (final flags in [(false, true), (true, false), (false, false)]) {
          final direct = await _previewPixels(
            renderer,
            view,
            false,
            includeText: flags.$1,
            includeImages: flags.$2,
          );
          final retained = await _previewPixels(
            renderer,
            view,
            true,
            includeText: flags.$1,
            includeImages: flags.$2,
          );
          _expectPixels(retained, direct);
          if (!flags.$1) expect(retained[(30 * 256 + 20) * 4 + 3], 0);
          if (!flags.$2) expect(retained[(40 * 256 + 180) * 4 + 3], 0);
        }
        expect(renderer.retainedStatistics!['builds'], builds);
      } finally {
        renderer.dispose();
      }
    });
  });

  test(
    'picture limits evict least recently used ranges and release old owners',
    () {
      final cache = ScenePictureCache(
        _recordRects,
        _smallBounds,
        pictureLimit: 2,
      );
      try {
        _paintCache(cache, [0]);
        _paintCache(cache, [256]);
        _paintCache(cache, [0]);
        _paintCache(cache, [512]);
        expect(cache.statistics['pictures'], 2);
        expect(cache.statistics['evictions'], 1);
        expect(cache.statistics['builds'], 3);
        _paintCache(cache, [0]);
        expect(cache.statistics['builds'], 3);
        _paintCache(cache, [256]);
        expect(cache.statistics['builds'], 4);
        expect(cache.statistics['evictions'], 2);
        expect(cache.statistics['disposedPictures'], 2);
        expect(
          cache.statistics['approximateBytes'],
          lessThanOrEqualTo(cache.byteLimit),
        );
        expect(cache.statistics['firstPaintRecordCpuMs'], isNotNull);
        cache.clear();
        expect(cache.statistics['pictures'], 0);
        expect(cache.statistics['approximateBytes'], 0);
        expect(cache.statistics['firstPaintRecordCpuMs'], isNull);
        _paintCache(cache, [0]);
        expect(cache.statistics['firstPaintRecordCpuMs'], isNotNull);
      } finally {
        cache.dispose();
      }
      expect(cache.statistics['pictures'], 0);
      expect(cache.statistics['approximateBytes'], 0);
      final disposed = cache.statistics['disposedPictures'];
      cache.dispose();
      expect(cache.statistics['disposedPictures'], disposed);
      expect(() => cache.setActiveIndices({0}), throwsStateError);
      expect(() => _paintCache(cache, [0]), throwsStateError);
    },
  );

  test(
    'approximate byte budgets reject and dispose oversized candidate pictures',
    () {
      for (final budget in [0, 1]) {
        var records = 0;
        final direct = <List<int>>[];
        final cache = ScenePictureCache(
          (indices, origin) {
            records++;
            return _recordRects(indices, origin);
          },
          _smallBounds,
          byteLimit: budget,
        );
        try {
          expect(
            _paintCache(cache, [
              0,
            ], paintDirect: (indices) => direct.add(indices)),
            isTrue,
          );
          expect(direct, [
            [0],
          ]);
          expect(cache.statistics['pictures'], 0);
          expect(cache.statistics['approximateBytes'], 0);
          expect(cache.statistics['directFallbacks'], 1);
          expect(records, budget == 0 ? 0 : 1);
          expect(cache.statistics['disposedPictures'], records);
        } finally {
          cache.dispose();
        }
      }
    },
  );

  test(
    'large local spans and active fragmentation fall back without retained growth',
    () {
      var records = 0;
      final direct = <List<int>>[];
      final cache = ScenePictureCache((indices, origin) {
        records++;
        return _recordRects(indices, origin);
      }, (index) => Bounds2(index * 1e9, 0, index * 1e9 + 10, 10));
      try {
        expect(
          _paintCache(cache, [
            0,
            1,
          ], paintDirect: (indices) => direct.add(indices)),
          isTrue,
        );
        expect(direct, [
          [0, 1],
        ]);
        expect(records, 0);
        cache.setActiveIndices({for (var i = 0; i <= 32; i++) i});
        expect(_paintCache(cache, [0, 1]), isFalse);
        expect(cache.statistics['activeOverflow'], isTrue);
        expect(cache.statistics['pictures'], 0);
        expect(cache.statistics['approximateBytes'], 0);
        cache.setActiveIndices({for (var i = 0; i < 32; i++) i});
        expect(_paintCache(cache, [0, 33], movingIndex: 33), isFalse);
        cache.setActiveIndices({});
        expect(_paintCache(cache, [1, 0]), isFalse);
        expect(_paintCache(cache, [0, 0]), isFalse);
        expect(records, 0);
      } finally {
        cache.dispose();
      }
    },
  );
}

BenchmarkScene _overlapScene() => BenchmarkScene([
  BenchmarkNode(
    id: 'lower-red',
    localBounds: Bounds2(20, 20, 140, 90),
    color: 0xffff0000,
    content: const ShapeContent(ShapeKind.rectangle),
  ),
  BenchmarkNode(
    id: 'active-blue',
    localBounds: Bounds2(10, 50, 180, 50),
    color: 0xff0000ff,
    strokeWidth: 20,
    content: StrokeContent([
      Point2(10, 50),
      Point2(180, 50),
    ], highlighter: true),
  ),
  BenchmarkNode(
    id: 'middle-green',
    localBounds: Bounds2(60, 15, 115, 90),
    color: 0xff008800,
    content: const ShapeContent(ShapeKind.rectangle),
  ),
  BenchmarkNode(
    id: 'active-purple',
    localBounds: Bounds2(75, 30, 125, 75),
    color: 0xff800080,
    content: const ShapeContent(ShapeKind.rectangle),
  ),
  BenchmarkNode(
    id: 'upper-orange',
    localBounds: Bounds2(40, 50, 210, 50),
    color: 0xffff8800,
    strokeWidth: 8,
    content: StrokeContent([
      Point2(40, 50),
      Point2(210, 50),
    ], highlighter: true),
  ),
]);

BenchmarkScene _richScene(double origin) => BenchmarkScene([
  BenchmarkNode(
    id: 'rtl',
    localBounds: Bounds2(0, 0, 128, 76),
    transform: Transform2.translation(origin + 8, origin + 12),
    content: const TextContent(
      'فكرة جديدة\nWhiteboard',
      sticky: true,
      rtl: true,
    ),
  ),
  BenchmarkNode(
    id: 'image',
    localBounds: Bounds2(0, 0, 64, 64),
    transform: Transform2.translation(origin + 160, origin + 24),
    content: const ImageContent('image-0'),
  ),
  BenchmarkNode(
    id: 'highlight',
    localBounds: Bounds2(0, 0, 200, 0),
    transform: Transform2.translation(origin + 12, origin + 100),
    color: 0xff0000ff,
    strokeWidth: 4,
    content: StrokeContent([Point2(0, 0), Point2(200, 0)], highlighter: true),
  ),
]);

Future<Uint8List> _previewPixels(
  SceneRenderer renderer,
  Bounds2 view,
  bool optimized, {
  int? movingIndex,
  Point2 delta = Point2.zero,
  bool includeText = true,
  bool includeImages = true,
}) async {
  final visible = renderer.index.query(view);
  if (movingIndex != null) {
    visible.remove(movingIndex);
    if (Transform2.translation(delta.x, delta.y)
        .mapBounds(renderer.scene.paintOrder[movingIndex].worldBounds)
        .intersects(view)) {
      visible.add(movingIndex);
      visible.sort();
    }
  }
  final recorder = ui.PictureRecorder();
  renderer.paint(
    ui.Canvas(recorder),
    visible,
    optimized: optimized,
    movingIndex: movingIndex,
    moveDelta: delta,
    includeText: includeText,
    includeImages: includeImages,
    viewport: view,
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

void _expectPixels(List<int> actual, List<int> expected) {
  expect(actual.length, expected.length);
  var maximum = 0;
  for (var i = 0; i < actual.length; i++) {
    final difference = (actual[i] - expected[i]).abs();
    if (difference > maximum) maximum = difference;
  }
  expect(maximum, lessThanOrEqualTo(1));
}

void _expectPixel(List<int> actual, List<int> expected, int x, int y) {
  final offset = (y * 256 + x) * 4;
  for (var channel = 0; channel < 4; channel++) {
    expect(actual[offset + channel], closeTo(expected[offset + channel], 1));
  }
}

int _ink(List<int> data) {
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

Bounds2 _smallBounds(int index) =>
    Bounds2((index % 3) * 20.0, 0, (index % 3) * 20.0 + 10, 10);

ui.Picture _recordRects(List<int> indices, Point2 origin) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (final index in indices) {
    final bounds = _smallBounds(index);
    canvas.drawRect(
      ui.Rect.fromLTRB(
        bounds.left - origin.x,
        bounds.top - origin.y,
        bounds.right - origin.x,
        bounds.bottom - origin.y,
      ),
      ui.Paint()..color = const ui.Color(0xff008800),
    );
  }
  return recorder.endRecording();
}

bool _paintCache(
  ScenePictureCache cache,
  List<int> visible, {
  int? movingIndex,
  void Function(List<int>)? paintDirect,
}) {
  final recorder = ui.PictureRecorder();
  try {
    return cache.paint(
      ui.Canvas(recorder),
      visible,
      Point2.zero,
      movingIndex: movingIndex,
      paintDirect: paintDirect ?? (_) {},
    );
  } finally {
    recorder.endRecording().dispose();
  }
}
