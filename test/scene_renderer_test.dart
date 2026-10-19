import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/scene_renderer.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

Future<ByteData> pixels(SceneRenderer renderer) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  renderer.paint(canvas, renderer.index.query(Bounds2(0, 0, 128, 128)));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(128, 128);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  testWidgets(
    'camera-relative rasterization keeps distant elements at the same pixel',
    (tester) async {
      await tester.runAsync(() async {
        for (final origin in [0.0, 1e6, 1e9]) {
          final renderer = await SceneRenderer.create(
            BenchmarkScene([
              BenchmarkNode(
                id: 'far',
                localBounds: Bounds2(0, 0, 10, 10),
                transform: Transform2.translation(
                  origin + 17.25,
                  origin + 17.25,
                ),
                content: const ShapeContent(ShapeKind.rectangle),
              ),
            ]),
          );
          try {
            final recorder = ui.PictureRecorder();
            final canvas = ui.Canvas(recorder);
            renderer.paint(canvas, [0], worldOrigin: Point2(origin, origin));
            final picture = recorder.endRecording();
            final image = await picture.toImage(64, 64);
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            image.dispose();
            picture.dispose();
            expect(
              data.getUint8((20 * 64 + 20) * 4 + 3),
              greaterThan(0),
              reason: 'origin=$origin',
            );
          } finally {
            renderer.dispose();
          }
        }
      });
    },
  );
  testWidgets(
    'committed transform refreshes culling and hit tests without changing source content',
    (tester) async {
      final scene = BenchmarkScene([
        BenchmarkNode(
          id: 'rect',
          localBounds: Bounds2(0, 0, 50, 50),
          content: const ShapeContent(ShapeKind.rectangle),
        ),
      ]);
      final renderer = await SceneRenderer.create(scene);
      addTearDown(renderer.dispose);
      final moved = scene.translated('rect', Point2(1000, 1000));
      renderer.synchronize(moved);
      expect(renderer.index.query(Bounds2(0, 0, 60, 60)), isEmpty);
      expect(renderer.hitTest(Point2(1020, 1020), worldTolerance: 0), 'rect');
      expect(renderer.hitTest(Point2(20, 20), worldTolerance: 0), isNull);
      expect(
        scene.paintOrder.single.worldBounds.contains(Point2(20, 20)),
        isTrue,
      );
      expect(renderer.revision, 1);
      final incompatible = BenchmarkScene([
        BenchmarkNode(
          id: 'rect',
          localBounds: Bounds2(0, 0, 50, 50),
          content: const ShapeContent(ShapeKind.ellipse),
        ),
      ]);
      expect(() => renderer.synchronize(incompatible), throwsArgumentError);
      expect(renderer.hitTest(Point2(1020, 1020), worldTolerance: 0), 'rect');
      expect(renderer.hitTest(Point2(1058, 1020), worldTolerance: 6), isNull);
    },
  );
  testWidgets('hit-testing honors rotated geometry and topmost paint order', (
    tester,
  ) async {
    final transform =
        Transform2.translation(100, 100) * Transform2.rotation(math.pi / 4);
    final scene = BenchmarkScene([
      BenchmarkNode(
        id: 'back',
        localBounds: Bounds2(0, 0, 80, 20),
        transform: transform,
        content: const ShapeContent(ShapeKind.rectangle),
      ),
      BenchmarkNode(
        id: 'front',
        localBounds: Bounds2(0, 0, 10, 10),
        transform: transform,
        content: const ShapeContent(ShapeKind.ellipse),
      ),
    ]);
    final renderer = await SceneRenderer.create(scene);
    addTearDown(renderer.dispose);
    expect(
      renderer.hitTest(transform.apply(Point2(5, 5)), worldTolerance: 0),
      'front',
    );
    expect(
      renderer.hitTest(transform.apply(Point2(60, 10)), worldTolerance: 0),
      'back',
    );
    expect(
      renderer.hitTest(transform.apply(Point2(-5, 15)), worldTolerance: 0),
      isNull,
    );
    expect(
      renderer.hitTest(transform.apply(Point2(82, 10)), worldTolerance: 2),
      'back',
    );
    renderer.dispose();
    renderer.dispose();
    expect(
      () => renderer.hitTest(Point2.zero, worldTolerance: 0),
      throwsStateError,
    );
  });

  testWidgets(
    'highlighter self-intersection has the same opacity as the rest of its stroke',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await SceneRenderer.create(
          BenchmarkScene([
            BenchmarkNode(
              id: 'highlight',
              localBounds: Bounds2(10, 10, 90, 90),
              content: StrokeContent([
                Point2(10, 10),
                Point2(90, 90),
                Point2(10, 90),
                Point2(90, 10),
              ], highlighter: true),
              strokeWidth: 10,
            ),
          ]),
        );
        try {
          final data = await pixels(renderer);
          int alpha(int x, int y) => data.getUint8((y * 128 + x) * 4 + 3);
          expect(alpha(50, 50), inInclusiveRange(65, 80));
          expect((alpha(50, 50) - alpha(30, 30)).abs(), lessThanOrEqualTo(1));
          expect(
            renderer.hitTest(Point2(50, 50), worldTolerance: 0),
            'highlight',
          );
          expect(renderer.hitTest(Point2(50, 20), worldTolerance: 0), isNull);
        } finally {
          renderer.dispose();
        }
      });
    },
  );

  testWidgets('image references reuse a real decoded asset and render pixels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final renderer = await SceneRenderer.create(
        BenchmarkScene([
          for (var i = 0; i < 2; i++)
            BenchmarkNode(
              id: 'image-$i',
              localBounds: Bounds2(0, 0, 50, 50),
              transform: Transform2.translation(i * 60.0, 0),
              content: const ImageContent('image-0'),
            ),
        ]),
        imageSide: 64,
      );
      try {
        expect(renderer.imageBytes, 64 * 64 * 4);
        final data = await pixels(renderer);
        expect(data.getUint8((20 * 128 + 20) * 4 + 3), 255);
        expect(data.getUint8((20 * 128 + 80) * 4 + 3), 255);
        expect(data.getUint8((100 * 128 + 100) * 4 + 3), 0);
      } finally {
        renderer.dispose();
      }
    });
  });

  testWidgets(
    'unknown synthetic assets fail instead of silently rendering a placeholder',
    (tester) async {
      await expectLater(
        SceneRenderer.create(
          BenchmarkScene([
            BenchmarkNode(
              id: 'bad',
              localBounds: Bounds2(0, 0, 50, 50),
              content: const ImageContent('missing'),
            ),
          ]),
        ),
        throwsArgumentError,
      );
    },
  );
}
