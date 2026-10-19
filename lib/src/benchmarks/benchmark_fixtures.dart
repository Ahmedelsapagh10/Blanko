import 'dart:math' as math;

import '../geometry/geometry.dart';
import 'benchmark_scene.dart';

enum SceneDistribution {
  sparse('Sparse'),
  normal('Normal editing'),
  dense('Dense'),
  imageHeavy('Image-heavy'),
  deepHierarchy('Deep hierarchy');

  const SceneDistribution(this.label);
  final String label;
}

final class BenchmarkFixture {
  const BenchmarkFixture({
    required this.scene,
    required this.distribution,
    required this.initialFocus,
    required this.canvasExtent,
  });

  final BenchmarkScene scene;
  final SceneDistribution distribution;
  final Point2 initialFocus;
  final double canvasExtent;

  static const seed = 0x5eed;
  static const imageAssetCount = 4;

  static BenchmarkFixture generate(SceneDistribution distribution) {
    final random = _DeterministicRandom(seed);
    final nodes = <BenchmarkNode>[];
    final sparse = distribution == SceneDistribution.sparse;
    final extent = sparse
        ? 100000.0
        : distribution == SceneDistribution.normal
        ? 8000.0
        : 1600.0;
    final height = sparse
        ? 100000.0
        : distribution == SceneDistribution.normal
        ? 4500.0
        : 900.0;
    String? parentId;
    if (distribution == SceneDistribution.deepHierarchy) {
      for (var i = 0; i < 64; i++) {
        final id = 'group-$i';
        nodes.add(
          BenchmarkNode(
            id: id,
            parentId: parentId,
            transform:
                Transform2.translation(2, 1) *
                Transform2.rotation(0.005) *
                Transform2.scale(1.001, 0.999),
            localBounds: Bounds2(0, 0, 0, 0),
            content: const GroupContent(),
          ),
        );
        parentId = id;
      }
    }
    for (var i = 0; i < 10000; i++) {
      // Spread categories through the paint order instead of stacking by type.
      final category = i % 100;
      final width = 32 + random.next() * 100;
      final nodeHeight = 24 + random.next() * 70;
      final x = random.next() * extent;
      final y = random.next() * height;
      BenchmarkContent content;
      var bounds = Bounds2(0, 0, width, nodeHeight);
      var strokeWidth = 1.5;
      if (category < 50) {
        content = ShapeContent(ShapeKind.values[i % ShapeKind.values.length]);
      } else if (category < 75) {
        final highlighter = i % 4 == 0;
        strokeWidth = highlighter ? 12 : 2.5;
        final points = [
          for (var p = 0; p < 24; p++)
            Point2(
              p * width / 23,
              nodeHeight * (0.5 + 0.4 * math.sin(p * 0.45 + i)),
            ),
        ];
        content = StrokeContent(points, highlighter: highlighter);
        bounds = Bounds2.fromPoints(points);
      } else if (category < 95) {
        final rtl = i.isEven;
        content = TextContent(
          rtl ? 'فكرة جديدة\nWhiteboard $i' : 'Explore ideas\nBoard $i',
          sticky: i % 3 != 0,
          rtl: rtl,
        );
        bounds = Bounds2(0, 0, 144, 76);
      } else if (category < 99) {
        final arrow = ArrowContent(Point2(0, nodeHeight), Point2(width, 0));
        content = arrow;
        bounds = Bounds2.fromPoints(arrow.points);
      } else {
        content = ImageContent('image-${(i ~/ 100) % imageAssetCount}');
        final large = distribution == SceneDistribution.imageHeavy;
        bounds = Bounds2(0, 0, large ? 1500 : 180, large ? 1100 : 135);
        strokeWidth = 0;
      }
      nodes.add(
        BenchmarkNode(
          id: 'element-$i',
          parentId: parentId,
          localBounds: bounds,
          content: content,
          transform:
              Transform2.translation(x, y) *
              Transform2.rotation((random.next() - 0.5) * 0.6),
          color: const [0xff2563eb, 0xff059669, 0xffd97706, 0xff9333ea][i % 4],
          strokeWidth: strokeWidth,
        ),
      );
    }
    return BenchmarkFixture(
      scene: BenchmarkScene(nodes),
      distribution: distribution,
      initialFocus: Point2(extent / 2, height / 2),
      canvasExtent: sparse ? 102000 : 4000,
    );
  }
}

// A fixed integer generator makes fixtures identical across native and web.
final class _DeterministicRandom {
  _DeterministicRandom(this._state);
  int _state;

  double next() {
    _state = (1664525 * _state + 1013904223) % 0x100000000;
    return _state / 0x100000000;
  }
}
