import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_canvas.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/benchmark_telemetry.dart';
import 'package:whiteboard/src/benchmarks/scene_layer_cache.dart';
import 'package:whiteboard/src/benchmarks/scene_renderer.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

void main() {
  test(
    'recording failure releases prepared subtrees and permits a clean retry',
    () {
      var fail = true;
      final cache = SceneLayerCache((indices, view, zoom) {
        if (fail && indices.first == 2) {
          throw StateError('controlled recording failure');
        }
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint());
        return recorder.endRecording();
      }, (i) => Bounds2(i * 20.0, 0, i * 20.0 + 20, 20));
      cache.setActiveIndices({1});
      final parent = ContainerLayer();
      final owner = LayerHandle<ContainerLayer>(parent);
      final context = PaintingContext(
        parent,
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      try {
        bool paint() => cache.paint(
          context,
          Offset.zero,
          [0, 1, 2],
          Bounds2(0, 0, 100, 100),
          1,
          1,
          paintDirect: (_) {},
        );
        expect(paint, throwsStateError);
        expect(cache.statistics['layers'], 0);
        expect(cache.statistics['approximatePictureBytes'], 0);
        expect(cache.statistics['disposedRanges'], 1);
        fail = false;
        expect(paint(), isTrue);
        expect(cache.statistics['layers'], 2);
      } finally {
        cache.dispose();
        owner.layer = null;
      }
      expect(cache.statistics['layers'], 0);
      expect(cache.statistics['approximatePictureBytes'], 0);
    },
  );

  testWidgets(
    'static engine subtrees survive interleaved preview cancel and commit',
    (tester) async {
      final renderer = await _renderer(tester, _overlap());
      final delta = ValueNotifier(Point2.zero);
      final pair = _Pair(renderer, delta)
        ..selected = 'active'
        ..dpr = 1.5;
      renderer.setRetainedActiveIndices([1]);
      pair.moving = 1;
      try {
        await pair.mount(tester);
        await pair.expectEqual(tester);
        final submitted = renderer.layerStatistics!['engineSubmissions'] as int;
        final builds = renderer.layerStatistics!['builds'];
        expect(submitted, 2);
        for (final dx in [30.0, -15.0, 0.0]) {
          delta.value = Point2(dx, 4);
          await tester.pump();
          await pair.expectEqual(tester);
          expect(renderer.layerStatistics!['engineSubmissions'], submitted);
          expect(renderer.layerStatistics!['builds'], builds);
        }
        delta.value = Point2.zero;
        await tester.pump();
        await pair.expectEqual(tester);
        renderer.synchronize(
          renderer.scene.translated('active', Point2(30, 4)),
        );
        await pair.mount(tester);
        await pair.expectEqual(tester);
        expect(renderer.layerStatistics!['engineSubmissions'], submitted);
        expect(renderer.layerStatistics!['reuses'], greaterThan(2));
      } finally {
        await tester.pumpWidget(const SizedBox());
        renderer.dispose();
        delta.dispose();
      }
    },
  );

  testWidgets(
    'inactive group commits remove stale pixels and rebuild static ranges',
    (tester) async {
      final renderer = await _renderer(
        tester,
        BenchmarkScene([
          BenchmarkNode(
            id: 'group',
            localBounds: Bounds2(0, 0, 1, 1),
            content: const GroupContent(),
          ),
          _shape('child', Bounds2(20, 20, 65, 65), 0xffff0000, parent: 'group'),
          _shape('active', Bounds2(160, 60, 190, 90), 0xff0000ff),
        ]),
      );
      final delta = ValueNotifier(Point2.zero);
      final pair = _Pair(renderer, delta);
      renderer.setRetainedActiveIndices([1]);
      try {
        await pair.mount(tester);
        await pair.expectEqual(tester);
        final before = await pair.layerPixels(tester);
        final builds = renderer.layerStatistics!['builds'] as int;
        renderer.synchronize(renderer.scene.translated('group', Point2(80, 0)));
        await pair.mount(tester);
        await pair.expectEqual(tester);
        final after = await pair.layerPixels(tester);
        expect(
          _pixel(before, 19 + 35, 13 + 35),
          isNot(_pixel(after, 19 + 35, 13 + 35)),
        );
        expect(renderer.layerStatistics!['invalidations'], greaterThan(0));
        expect(renderer.layerStatistics!['builds'], greaterThan(builds));
        expect(renderer.hitTest(Point2(35, 35), worldTolerance: 0), isNull);
        expect(renderer.hitTest(Point2(115, 35), worldTolerance: 0), 'child');
      } finally {
        await tester.pumpWidget(const SizedBox());
        renderer.dispose();
        delta.dispose();
      }
    },
  );

  testWidgets(
    'fractional camera zoom DPR and membership preserve rich scene pixels',
    (tester) async {
      final renderer = await _renderer(tester, _rich(0));
      final delta = ValueNotifier(Point2.zero);
      final pair = _Pair(renderer, delta);
      try {
        for (final values in [
          (0.0, 0.0, 1.0, 1.0),
          (9.25, 3.5, 1.25, 2.0),
          (110.5, 12.25, .8, 1.5),
          (-20.25, -9.5, 1.75, 1.0),
        ]) {
          pair.zoom = values.$3;
          pair.dpr = values.$4;
          pair.view = Bounds2(
            values.$1,
            values.$2,
            values.$1 + 256 / pair.zoom,
            values.$2 + 128 / pair.zoom,
          );
          await pair.mount(tester);
          await pair.expectEqual(tester);
          expect(
            renderer.layerStatistics!['estimatedRasterExposureBytes'],
            lessThanOrEqualTo(64 * 1024 * 1024),
          );
        }
        expect(renderer.layerStatistics!['clears'], greaterThan(1));
        expect(renderer.imageBytes, 64 * 64 * 4);
        expect(renderer.textLayoutCount, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        renderer.dispose();
        delta.dispose();
      }
    },
  );

  testWidgets(
    'large positive and negative world coordinates retain RTL and images',
    (tester) async {
      for (final origin in [1e9, -1e9]) {
        final renderer = await _renderer(tester, _rich(origin));
        final delta = ValueNotifier(Point2.zero);
        final pair = _Pair(renderer, delta)
          ..zoom = 1.25
          ..view = Bounds2(
            origin + .25,
            origin + .5,
            origin + 205.05,
            origin + 102.9,
          );
        try {
          await pair.mount(tester);
          await pair.expectEqual(tester);
          renderer.synchronize(
            renderer.scene.translated('image', Point2(.5, .25)),
          );
          await pair.mount(tester);
          await pair.expectEqual(tester);
          expect(renderer.layerStatistics!['builds'], greaterThan(0));
        } finally {
          await tester.pumpWidget(const SizedBox());
          renderer.dispose();
          delta.dispose();
        }
        expect(renderer.ownedImageHandles, 0);
        expect(renderer.ownedParagraphs, 0);
      }
    },
  );

  testWidgets(
    'viewport clip contains static and live geometry at nonzero paint offset',
    (tester) async {
      final renderer = await _renderer(
        tester,
        BenchmarkScene([
          _shape('wide', Bounds2(-40, -30, 290, 160), 0xffff0000),
          _shape('active', Bounds2(235, 85, 310, 160), 0x800000ff),
        ]),
      );
      final delta = ValueNotifier(Point2.zero);
      final pair = _Pair(renderer, delta)..moving = 1;
      renderer.setRetainedActiveIndices([1]);
      try {
        await pair.mount(tester);
        await pair.expectEqual(tester);
        var pixels = await pair.layerPixels(tester);
        for (final point in [(18, 40), (275, 40), (50, 12), (50, 141)]) {
          expect(_pixel(pixels, point.$1, point.$2), 0xff7b315d);
        }
        delta.value = Point2(-30, -20);
        await tester.pump();
        await pair.expectEqual(tester);
        pixels = await pair.layerPixels(tester);
        expect(_pixel(pixels, 280, 140), 0xff7b315d);
        pair.dpr = 1.5;
        await pair.mount(tester);
        await pair.expectEqual(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        renderer.dispose();
        delta.dispose();
      }
    },
  );

  testWidgets(
    'renderer replacement detach and disposal release layer ownership',
    (tester) async {
      final first = await _renderer(tester, _overlap());
      final second = await _renderer(tester, _rich(0));
      final delta = ValueNotifier(Point2.zero);
      final pair = _Pair(first, delta);
      try {
        await pair.mount(tester);
        await pair.expectEqual(tester);
        final firstBuilds = first.layerStatistics!['builds'];
        await tester.pumpWidget(const SizedBox());
        delta.value = Point2(4, 2);
        await tester.pump();
        expect(first.layerStatistics!['builds'], firstBuilds);
        await pair.mount(tester);
        await pair.expectEqual(tester);
        pair.renderer = second;
        await pair.mount(tester);
        first.dispose();
        await pair.expectEqual(tester);
        expect(first.layerStatistics!['disposed'], isTrue);
        expect(first.layerStatistics!['layers'], 0);
        expect(first.layerStatistics!['approximatePictureBytes'], 0);
        expect(first.layerStatistics!['disposedRanges'], greaterThan(0));
      } finally {
        await tester.pumpWidget(const SizedBox());
        first.dispose();
        second.dispose();
        delta.dispose();
      }
      expect(second.layerStatistics!['layers'], 0);
      expect(second.ownedImageHandles, 0);
      expect(second.ownedParagraphs, 0);
    },
  );

  testWidgets('text and image omission use complete direct fallback', (
    tester,
  ) async {
    final renderer = await _renderer(tester, _rich(0));
    final delta = ValueNotifier(Point2.zero);
    final pair = _Pair(renderer, delta);
    try {
      await pair.mount(tester);
      await pair.expectEqual(tester);
      final builds = renderer.layerStatistics!['builds'];
      for (final options in [(false, true), (true, false), (false, false)]) {
        pair.includeText = options.$1;
        pair.includeImages = options.$2;
        await pair.mount(tester);
        await pair.expectEqual(tester);
        expect(renderer.layerStatistics!['builds'], builds);
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      renderer.dispose();
      delta.dispose();
    }
  });

  testWidgets(
    'bounded layer budgets reject without partially painting cached content',
    (tester) async {
      for (final budget in [
        (0, 1000000, 4),
        (1, 1000000, 4),
        (1000000, 1, 4),
        (1000000, 1000000, 1),
      ]) {
        final fixture = _CacheFixture(
          pictureBytes: budget.$1,
          exposure: budget.$2,
          layers: budget.$3,
        );
        fixture.cache.setActiveIndices({1});
        try {
          await fixture.mount(tester);
          expect(fixture.accepted, isFalse);
          expect(fixture.direct, [0, 1, 2]);
          expect(fixture.cache.statistics['layers'], 0);
          expect(fixture.cache.statistics['approximatePictureBytes'], 0);
          expect(fixture.cache.statistics['directFallbacks'], 1);
        } finally {
          await tester.pumpWidget(const SizedBox());
          fixture.cache.dispose();
        }
      }
    },
  );

  testWidgets(
    'unsupported order and active overflow fallback preserve exact caller order',
    (tester) async {
      for (final order in [
        [2, 0, 1],
        [0, 1, 1, 2],
      ]) {
        final fixture = _CacheFixture()..visible = order;
        try {
          await fixture.mount(tester);
          expect(fixture.accepted, isFalse);
          expect(fixture.direct, order);
          expect(fixture.cache.statistics['layers'], 0);
        } finally {
          await tester.pumpWidget(const SizedBox());
          fixture.cache.dispose();
        }
      }
      final fixture = _CacheFixture();
      fixture.cache.setActiveIndices(
        Set<int>.from(List.generate(33, (i) => i)),
      );
      try {
        await fixture.mount(tester);
        expect(fixture.accepted, isFalse);
        expect(fixture.direct, [0, 1, 2]);
        expect(fixture.cache.statistics['activeOverflow'], isTrue);
        fixture.cache.setActiveIndices({});
        await fixture.mount(tester);
        expect(fixture.accepted, isTrue);
        expect(fixture.cache.statistics['builds'], greaterThan(0));
      } finally {
        await tester.pumpWidget(const SizedBox());
        fixture.cache.dispose();
      }
      expect(() => fixture.cache.setActiveIndices({}), throwsStateError);
    },
  );
}

Future<SceneRenderer> _renderer(
  WidgetTester tester,
  BenchmarkScene scene,
) async {
  late SceneRenderer renderer;
  await tester.runAsync(() async {
    renderer = await SceneRenderer.create(
      scene,
      retainLayers: true,
      imageSide: 64,
    );
  });
  return renderer;
}

class _Pair {
  _Pair(this.renderer, this.delta);
  SceneRenderer renderer;
  final ValueNotifier<Point2> delta;
  final directKey = GlobalKey();
  final layerKey = GlobalKey();
  Bounds2 view = Bounds2(0, 0, 256, 128);
  double zoom = 1;
  double dpr = 1;
  int? moving;
  String? selected;
  bool includeText = true;
  bool includeImages = true;

  BenchmarkPainter painter(bool optimized) => BenchmarkPainter(
    renderer: renderer,
    viewport: view,
    zoom: zoom,
    selected: selected,
    movingIndex: moving,
    moveDelta: delta,
    telemetry: BenchmarkTelemetry(),
    optimized: optimized,
    devicePixelRatio: dpr,
    includeText: includeText,
    includeImages: includeImages,
  );

  Future<void> mount(WidgetTester tester) async {
    Widget frame(bool retained) => RepaintBoundary(
      key: retained ? layerKey : directKey,
      child: SizedBox(
        width: 320,
        height: 180,
        child: ColoredBox(
          color: const Color(0xff7b315d),
          child: Stack(
            children: [
              Positioned(
                left: 19,
                top: 13,
                width: 256,
                height: 128,
                child: retained
                    ? BenchmarkLayerCanvas(painter: painter(true))
                    : CustomPaint(painter: painter(false)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [frame(false), frame(true)],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  Future<Uint8List> layerPixels(WidgetTester tester) =>
      _pixels(tester, layerKey, pixelRatio: dpr);
  Future<void> expectEqual(WidgetTester tester) async {
    final direct = await _pixels(tester, directKey, pixelRatio: dpr);
    final retained = await layerPixels(tester);
    expect(retained.length, direct.length);
    var maximumError = 0;
    var changedChannels = 0;
    for (var i = 0; i < direct.length; i++) {
      final error = (direct[i] - retained[i]).abs();
      if (error > maximumError) maximumError = error;
      if (error > 1) changedChannels++;
    }
    if (changedChannels > 0) {
      final width = (320 * dpr).ceil();
      final points = <String>[];
      for (var i = 0; i < direct.length && points.length < 12; i += 4) {
        if ((direct[i] - retained[i]).abs() > 1 ||
            (direct[i + 1] - retained[i + 1]).abs() > 1) {
          points.add(
            "${(i ~/ 4) % width},${(i ~/ 4) ~/ width}: ${direct.sublist(i, i + 4)} / ${retained.sublist(i, i + 4)}",
          );
        }
      }
      debugPrint(
        "Layer pixels zoom=$zoom DPR=$dpr view=${view.left},${view.top}: $points",
      );
    }
    expect(
      changedChannels,
      0,
      reason:
          'Max channel error $maximumError; view=$view zoom=$zoom dpr=$dpr; composited output differs from direct drawing.',
    );
  }
}

Future<Uint8List> _pixels(
  WidgetTester tester,
  GlobalKey key, {
  double pixelRatio = 1,
}) async {
  late Uint8List result;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      result = Uint8List.fromList(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  return result;
}

int _pixel(Uint8List data, int x, int y) {
  final i = (y * 320 + x) * 4;
  return (data[i + 3] << 24) |
      (data[i] << 16) |
      (data[i + 1] << 8) |
      data[i + 2];
}

BenchmarkNode _shape(String id, Bounds2 bounds, int color, {String? parent}) =>
    BenchmarkNode(
      id: id,
      parentId: parent,
      localBounds: bounds,
      color: color,
      content: const ShapeContent(ShapeKind.rectangle),
    );

BenchmarkScene _overlap() => BenchmarkScene([
  _shape('lower', Bounds2(15, 15, 180, 105), 0x99ff0000),
  BenchmarkNode(
    id: 'active',
    localBounds: Bounds2(10, 50, 210, 50),
    color: 0xff0000ff,
    strokeWidth: 20,
    content: StrokeContent([
      Point2(10, 50),
      Point2(210, 50),
    ], highlighter: true),
  ),
  _shape('upper', Bounds2(60, 20, 130, 100), 0x99008800),
]);

BenchmarkScene _rich(double origin) => BenchmarkScene([
  BenchmarkNode(
    id: 'rtl',
    localBounds: Bounds2(0, 0, 130, 75),
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

class _CacheFixture {
  _CacheFixture({
    int pictureBytes = 1000000,
    int exposure = 1000000,
    int layers = 4,
  }) {
    cache = SceneLayerCache(
      (indices, view, zoom) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final index in indices) {
          canvas.drawRect(
            Rect.fromLTWH(10.0 + index * 10, 10, 8, 8),
            Paint()..color = const Color(0x800000ff),
          );
        }
        return recorder.endRecording();
      },
      (i) => Bounds2(10.0 + i * 10, 10, 18.0 + i * 10, 18),
      pictureByteLimit: pictureBytes,
      rasterEstimateLimit: exposure,
      layerLimit: layers,
    );
  }
  late final SceneLayerCache cache;
  List<int> visible = [0, 1, 2];
  List<int> direct = [];
  bool? accepted;
  Future<void> mount(WidgetTester tester) async {
    direct = [];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _CacheWidget(this),
      ),
    );
    expect(tester.takeException(), isNull);
  }
}

class _CacheWidget extends LeafRenderObjectWidget {
  const _CacheWidget(this.fixture);
  final _CacheFixture fixture;
  @override
  RenderObject createRenderObject(BuildContext context) => _CacheBox(fixture);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _CacheBox renderObject,
  ) {
    renderObject.markNeedsPaint();
  }
}

class _CacheBox extends RenderBox {
  _CacheBox(this.fixture);
  final _CacheFixture fixture;
  @override
  bool get alwaysNeedsCompositing => true;
  @override
  void performLayout() {
    size = constraints.constrain(const Size(100, 100));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    fixture.accepted = fixture.cache.paint(
      context,
      offset,
      fixture.visible,
      Bounds2(0, 0, 100, 100),
      1,
      1,
      paintDirect: (indices) {
        fixture.direct.addAll(indices);
      },
    );
    if (!fixture.accepted!) fixture.direct.addAll(fixture.visible);
  }
}
