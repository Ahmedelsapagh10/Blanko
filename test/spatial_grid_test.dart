import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/spatial/spatial_grid.dart';

void main() {
  test(
    'incremental updates match rebuilds through cell and overflow transitions',
    () {
      final bounds = [
        Bounds2(-10, -10, 10, 10),
        Bounds2(0, 0, 100, 100),
        Bounds2(1e6, 1e6, 1e6 + 10, 1e6 + 10),
      ];
      final grid = SpatialGrid(bounds);
      final random = math.Random(14);
      for (var i = 0; i < 200; i++) {
        final index = i % 3;
        final delta = Transform2.translation(
          random.nextDouble() * 4000 - 2000,
          random.nextDouble() * 4000 - 2000,
        );
        final next = i % 11 == 0
            ? Bounds2(-1000000, -1000000, 1000000, 1000000)
            : delta.mapBounds(Bounds2(0, 0, 200, 200));
        bounds[index] = next;
        grid.update(index, next);
        final rebuilt = SpatialGrid(bounds);
        for (final area in [
          Bounds2(-256, -256, 256, 256),
          next,
          Bounds2(-1e9, -1e9, 1e9, 1e9),
        ]) {
          expect(grid.query(area), rebuilt.query(area));
        }
      }
      final before = grid.query(Bounds2(-1e9, -1e9, 1e9, 1e9));
      expect(
        () => grid.update(0, Bounds2(1e300, 0, 1e300, 1)),
        throwsArgumentError,
      );
      expect(grid.query(Bounds2(-1e9, -1e9, 1e9, 1e9)), before);
    },
  );
  test(
    'grid queries match brute-force culling, including negatives and boundaries',
    () {
      final random = math.Random(654);
      final bounds = [
        for (var i = 0; i < 1000; i++)
          Bounds2(0, 0, random.nextDouble() * 100, random.nextDouble() * 100),
      ];
      final shifted = [
        for (final bound in bounds)
          Transform2.translation(
            random.nextDouble() * 4000 - 2000,
            random.nextDouble() * 4000 - 2000,
          ).mapBounds(bound),
        Bounds2(-1000000, -1000000, 1000000, 1000000),
        Bounds2(256, 256, 256, 256),
      ];
      final grid = SpatialGrid(shifted);
      final queries = [
        Bounds2(-1e9, -1e9, 1e9, 1e9),
        Bounds2(256, 256, 256, 256),
        for (var i = 0; i < 100; i++)
          Transform2.translation(
            random.nextDouble() * 4000 - 2000,
            random.nextDouble() * 4000 - 2000,
          ).mapBounds(Bounds2(0, 0, 300, 200)),
      ];
      for (final query in queries) {
        expect(grid.query(query), [
          for (var i = 0; i < shifted.length; i++)
            if (shifted[i].intersects(query)) i,
        ]);
      }
    },
  );

  test('grid rejects invalid sizes and unsafe integer ranges', () {
    expect(() => SpatialGrid([], cellSize: 0), throwsArgumentError);
    expect(
      () => SpatialGrid([Bounds2(1e300, 0, 1e300, 1)]),
      throwsArgumentError,
    );
    expect(
      () => SpatialGrid([]).query(Bounds2(-1e300, 0, 1e300, 1)),
      throwsArgumentError,
    );
    expect(SpatialGrid([]).query(Bounds2(0, 0, 0, 0)), isEmpty);
  });
}
