import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_scene.dart';
import 'package:whiteboard/src/benchmarks/benchmark_fixtures.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

void main() {
  test(
    'a leaf update shares unrelated geometry and keeps prior snapshots immutable',
    () {
      final original = BenchmarkFixture.generate(SceneDistribution.dense).scene;
      expect(identical(original.transformed({}), original), isTrue);
      expect(
        identical(original.translated('element-0', Point2.zero), original),
        isTrue,
      );
      var current = original;
      for (var i = 0; i < 1000; i++) {
        current = current.translated('element-0', Point2(i.isEven ? 1 : -1, 0));
        expect(current.delta!.resolvedCount, 1);
        expect(current.delta!.paintIndices, [0]);
        expect(
          identical(current.paintOrder[9999], original.paintOrder[9999]),
          isTrue,
        );
        expect(identical(current.nodes[9999], original.nodes[9999]), isTrue);
      }
      expect(
        current.paintOrder.first.worldTransform.tx,
        closeTo(original.paintOrder.first.worldTransform.tx, 1e-8),
      );
      expect(() => current.nodes[0] = current.nodes[1], throwsUnsupportedError);
      expect(() => current.delta!.paintIndices.add(5), throwsUnsupportedError);
    },
  );
  test(
    'batched parent and child transforms equal a full resolve without ordering dependence',
    () {
      final scene = BenchmarkScene([
        BenchmarkNode(
          id: 'g',
          localBounds: Bounds2(0, 0, 0, 0),
          content: const GroupContent(),
          transform: Transform2.rotation(.4),
        ),
        BenchmarkNode(
          id: 'c',
          parentId: 'g',
          localBounds: Bounds2(0, 0, 10, 20),
          content: const ShapeContent(ShapeKind.rectangle),
        ),
        BenchmarkNode(
          id: 'other',
          localBounds: Bounds2(0, 0, 10, 10),
          content: const ShapeContent(ShapeKind.ellipse),
        ),
      ]);
      final random = math.Random(45);
      var current = scene;
      for (var i = 0; i < 100; i++) {
        current = current.transformed({
          'c': Transform2.rotation(random.nextDouble()),
          'g': Transform2.translation(i * 2, i * 3) * Transform2.scale(2, .5),
        });
        final reference = BenchmarkScene(current.nodes);
        expect(current.delta!.resolvedCount, 2);
        expect(
          current.paintOrder[0].worldTransform,
          reference.paintOrder[0].worldTransform,
        );
        expect(
          current.paintOrder[0].worldBounds,
          reference.paintOrder[0].worldBounds,
        );
        expect(identical(current.paintOrder[1], scene.paintOrder[1]), isTrue);
      }
      expect(
        () => scene.transformed({'unknown': Transform2.identity}),
        throwsArgumentError,
      );
    },
  );
}
