import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_fixtures.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/frame_samples.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

BenchmarkNode node(
  String id, {
  String? parentId,
  bool group = false,
  double x = 0,
}) => BenchmarkNode(
  id: id,
  parentId: parentId,
  transform: Transform2.translation(x, 0),
  localBounds: Bounds2(0, 0, 10, 10),
  content: group
      ? const GroupContent()
      : const ShapeContent(ShapeKind.rectangle),
);

void main() {
  test('completed world movement preserves parent and all unrelated nodes', () {
    final scene = BenchmarkScene([
      BenchmarkNode(
        id: 'g',
        localBounds: Bounds2(0, 0, 1, 1),
        content: const GroupContent(),
        transform:
            Transform2.translation(120, -50) *
            Transform2.rotation(0.7) *
            Transform2.scale(2, 0.5),
      ),
      node('child', parentId: 'g', x: 30),
      node('unrelated', x: 900),
    ]);
    final before = scene.paintOrder.first.worldTransform;
    final moved = scene.translated('child', Point2(40, -70));
    final after = moved.paintOrder.first.worldTransform;
    for (final point in [Point2.zero, Point2(10, 10)]) {
      expect(
        after.apply(point).distanceTo(before.apply(point) + Point2(40, -70)),
        lessThan(1e-8),
      );
    }
    expect(moved.nodes[1].parentId, 'g');
    expect(moved.nodes[2], same(scene.nodes[2]));
    expect(scene.nodes[1].transform, Transform2.translation(30, 0));
    expect(() => scene.translated('missing', Point2.zero), throwsArgumentError);
  });

  test('frame series distinguish CPU, raster, and total-span measurements', () {
    final samples = FrameSamples()
      ..add(buildMicros: 1000, rasterMicros: 2000, totalMicros: 5000);
    expect(samples.build.percentileMs(95), 1);
    expect(samples.raster.percentileMs(95), 2);
    expect(samples.totalSpan.percentileMs(95), 5);
    expect(samples.percentileMs(95), 2);
    samples.clear();
    expect(samples.build.count, 0);
    expect(samples.totalSpan.count, 0);
  });
  test('hierarchy resolves parent transforms and retains subtree z-order', () {
    final scene = BenchmarkScene([
      node('group', group: true, x: 10),
      node('above', x: 20),
      node('child', parentId: 'group', x: 30),
    ]);
    expect(scene.paintOrder.map((entry) => entry.node.id), ['child', 'above']);
    expect(
      scene.paintOrder.first.worldTransform.apply(Point2.zero),
      Point2(40, 0),
    );
    expect(() => scene.nodes.add(node('unexpected')), throwsUnsupportedError);
  });

  test(
    'hierarchy rejects duplicates, cycles, self-parenting, and missing/leaf parents',
    () {
      expect(() => BenchmarkScene([node('a'), node('a')]), throwsArgumentError);
      expect(
        () => BenchmarkScene([node('a', group: true, parentId: 'a')]),
        throwsArgumentError,
      );
      expect(
        () => BenchmarkScene([
          node('a', group: true, parentId: 'b'),
          node('b', group: true, parentId: 'a'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => BenchmarkScene([node('a', parentId: 'missing')]),
        throwsArgumentError,
      );
      expect(
        () => BenchmarkScene([node('a'), node('b', parentId: 'a')]),
        throwsArgumentError,
      );
    },
  );

  test('deep hierarchy resolves iteratively without recursion overflow', () {
    final scene = BenchmarkScene([
      for (var i = 0; i < 5000; i++)
        node('g$i', group: true, parentId: i == 0 ? null : 'g${i - 1}', x: 1),
      node('leaf', parentId: 'g4999', x: 20),
    ]);
    expect(
      scene.paintOrder.single.worldTransform.apply(Point2.zero),
      Point2(5020, 0),
    );
  });

  for (final distribution in SceneDistribution.values) {
    test(
      '${distribution.label} fixture has the exact benchmark mix and valid assets',
      () {
        final fixture = BenchmarkFixture.generate(distribution);
        final contents = fixture.scene.paintOrder
            .map((entry) => entry.node.content)
            .toList();
        expect(contents.length, 10000);
        expect(contents.whereType<ShapeContent>().length, 5000);
        expect(contents.whereType<StrokeContent>().length, 2500);
        expect(contents.whereType<TextContent>().length, 2000);
        expect(contents.whereType<ArrowContent>().length, 400);
        expect(contents.whereType<ImageContent>().length, 100);
        expect(
          contents
              .whereType<ImageContent>()
              .map((entry) => entry.assetId)
              .toSet()
              .length,
          BenchmarkFixture.imageAssetCount,
        );
        expect(
          fixture.scene.nodes
              .where((node) => node.content is GroupContent)
              .length,
          distribution == SceneDistribution.deepHierarchy ? 64 : 0,
        );
        for (final entry in fixture.scene.paintOrder) {
          expect(entry.worldBounds.left.isFinite, isTrue);
        }
        final repeat = BenchmarkFixture.generate(distribution);
        for (final index in [0, 50, 99, 1234, 9999]) {
          final a = fixture.scene.paintOrder[index];
          final b = repeat.scene.paintOrder[index];
          expect(a.worldBounds, b.worldBounds);
          expect(
            a.worldTransform.apply(Point2.zero),
            b.worldTransform.apply(Point2.zero),
          );
        }
      },
    );
  }

  test('arrow bounds contain the head even with a very shallow angle', () {
    final arrow = ArrowContent(Point2(0, 1), Point2(100, 0));
    final bounds = Bounds2.fromPoints(arrow.points);
    expect(bounds.top, lessThan(0));
    for (final point in arrow.points) {
      expect(bounds.contains(point), isTrue);
    }
  });

  test(
    'frame samples use nearest-rank percentiles, bound memory, and reset',
    () {
      final samples = FrameSamples();
      expect(samples.percentileMs(95), isNull);
      for (var i = 1; i <= 100; i++) {
        samples.add(buildMicros: i * 1000, rasterMicros: i * 500);
      }
      expect(samples.percentileMs(50), 50);
      expect(samples.percentileMs(95), 95);
      expect(samples.percentileMs(99), 99);
      for (var i = 0; i < FrameSamples.capacity; i++) {
        samples.add(buildMicros: 2, rasterMicros: 1000);
      }
      expect(samples.count, FrameSamples.capacity);
      expect(samples.percentileMs(99), 1);
      expect(() => samples.percentileMs(double.nan), throwsArgumentError);
      expect(
        () => samples.add(buildMicros: -1, rasterMicros: 0),
        throwsArgumentError,
      );
      samples.clear();
      expect(samples.count, 0);
      // The longer soak must retain early slow frames as well as its fast tail.
      final soak = FrameSamples(limit: 12000);
      for (var i = 0; i < 10000; i++) {
        soak.add(buildMicros: i < 1000 ? 100000 : 1000, rasterMicros: 1000);
      }
      expect(soak.count, 10000);
      expect(soak.percentileMs(95), 100);
      expect(() => FrameSamples(limit: 0), throwsArgumentError);
    },
  );
}
