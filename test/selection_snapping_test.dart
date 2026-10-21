import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/selection_snapping.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

List<Object> guideValues(SnapResult result) => [
  for (final guide in result.guides)
    (guide.vertical, guide.position, guide.start, guide.end),
];

void main() {
  test('nearby object edges and centers snap on independent axes', () {
    final result = snapMove(
      movingBounds: Bounds2(0, 0, 20, 10),
      delta: Point2(77, 48),
      candidates: [Bounds2(100, 100, 130, 150), Bounds2(200, 50, 250, 80)],
      tolerance: 4,
    );
    expect(result.delta, Point2(80, 50));
    final vertical = result.guides.singleWhere((g) => g.vertical);
    expect(vertical.position, 100);
    expect((vertical.start, vertical.end), (50, 150));
    final horizontal = result.guides.singleWhere((g) => !g.vertical);
    expect(horizontal.position, 50);
    expect((horizontal.start, horizontal.end), (80, 250));
    expect(() => result.guides.add(vertical), throwsUnsupportedError);
  });

  test(
    'equal-distance snap ties are stable independent of candidate order',
    () {
      final candidates = [
        Bounds2(24, 80, 24, 100),
        Bounds2(16, 200, 16, 210),
        Bounds2(16, 40, 16, 50),
      ];
      SnapResult run(Iterable<Bounds2> input) => snapMove(
        movingBounds: Bounds2(0, 0, 20, 20),
        delta: Point2.zero,
        candidates: input,
        tolerance: 4,
      );
      final first = run(candidates), second = run(candidates.reversed);
      expect(first.delta, Point2(-4, 0));
      expect(second.delta, first.delta);
      expect(guideValues(second), guideValues(first));
      expect(first.guides.single.position, 16);
      expect(first.guides.single.end, 50);
    },
  );

  test('screen-space tolerance stays constant at different camera zooms', () {
    for (final zoom in [.25, 1.0, 8.0]) {
      final candidate = Bounds2(100, 100, 130, 140);
      final result = snapMove(
        movingBounds: Bounds2(0, 0, 10, 10),
        delta: Point2(90 - 5 / zoom, 0),
        candidates: [candidate],
        tolerance: 6 / zoom,
      );
      expect(result.delta.x, closeTo(90, 1e-9));
      final outside = snapMove(
        movingBounds: Bounds2(0, 0, .1 / zoom, .1 / zoom),
        delta: Point2(100 - 7 / zoom, 0),
        candidates: [Bounds2(100, 100, 100, 100)],
        tolerance: 6 / zoom,
      );
      expect(outside.delta.x, closeTo(100 - 7 / zoom, 1e-9));
      expect(outside.guides, isEmpty);
    }
  });

  test('optional grid snapping respects tolerance and closer objects', () {
    final onGrid = snapMove(
      movingBounds: Bounds2(0, 0, 5, 5),
      delta: Point2(38, -41),
      candidates: const [],
      tolerance: 4,
      gridSpacing: 20,
    );
    expect(onGrid.delta, Point2(40, -40));
    expect(onGrid.guides.length, 2);
    final nearerObject = snapMove(
      movingBounds: Bounds2(0, 0, 5, 5),
      delta: Point2(38, -41),
      candidates: [Bounds2(44, 200, 44, 200)],
      tolerance: 4,
      gridSpacing: 20,
    );
    expect(nearerObject.delta, Point2(39, -40));
    final distantGrid = snapMove(
      movingBounds: Bounds2(0, 0, 5, 5),
      delta: Point2(30, 30),
      candidates: const [],
      tolerance: 3,
      gridSpacing: 20,
    );
    expect(distantGrid.delta, Point2(30, 30));
    expect(distantGrid.guides, isEmpty);
    expect(
      () => snapMove(
        movingBounds: Bounds2(0, 0, 1, 1),
        delta: Point2.zero,
        candidates: const [],
        tolerance: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => snapMove(
        movingBounds: Bounds2(0, 0, 1, 1),
        delta: Point2.zero,
        candidates: const [],
        tolerance: 1,
        gridSpacing: 0,
      ),
      throwsArgumentError,
    );
  });

  test('candidate work is bounded to128 supplied spatial hits', () {
    var visited = 0;
    Iterable<Bounds2> candidates() sync* {
      for (var i = 0; i < 1000; i++) {
        visited++;
        yield Bounds2(1000 + i.toDouble(), 1000, 1010 + i.toDouble(), 1010);
      }
    }

    snapMove(
      movingBounds: Bounds2(0, 0, 10, 10),
      delta: Point2.zero,
      candidates: candidates(),
      tolerance: 6,
    );
    expect(visited, 128);
  });

  test(
    'all alignments use supplied visual world bounds and preserve sizes',
    () {
      final a = ElementId('a'), b = ElementId('b');
      final rotated =
          Transform2.translation(-100, -70) * Transform2.rotation(math.pi / 4);
      final visual = rotated.mapBounds(Bounds2(0, 0, 40, 20));
      final bounds = {a: visual, b: Bounds2(10, 30, 80, 50)};
      for (final action in [
        'align-left',
        'hcenter',
        'right',
        'top',
        'vcenter',
        'bottom',
      ]) {
        final offsets = selectionLayout(bounds, action);
        final positions = {
          for (final e in bounds.entries)
            e.key: Transform2.translation(
              offsets[e.key]!.x,
              offsets[e.key]!.y,
            ).mapBounds(e.value),
        };
        for (final id in bounds.keys) {
          expect(positions[id]!.width, closeTo(bounds[id]!.width, 1e-9));
          expect(positions[id]!.height, closeTo(bounds[id]!.height, 1e-9));
        }
        final first = positions[a]!, second = positions[b]!;
        switch (action) {
          case 'align-left':
            expect(first.left, closeTo(second.left, 1e-9));
          case 'hcenter':
            expect(first.center.x, closeTo(second.center.x, 1e-9));
          case 'right':
            expect(first.right, closeTo(second.right, 1e-9));
          case 'top':
            expect(first.top, closeTo(second.top, 1e-9));
          case 'vcenter':
            expect(first.center.y, closeTo(second.center.y, 1e-9));
          case 'bottom':
            expect(first.bottom, closeTo(second.bottom, 1e-9));
        }
      }
    },
  );

  test('distribution equalizes mixed-size gaps and preserves outer extent', () {
    final a = ElementId('a'), b = ElementId('b'), c = ElementId('c');
    final bounds = {
      c: Bounds2(80, 90, 100, 110),
      a: Bounds2(-100, -90, -90, -80),
      b: Bounds2(-50, 0, -20, 30),
    };
    for (final horizontal in [true, false]) {
      final result = selectionLayout(
        bounds,
        horizontal ? 'distribute-h' : 'distribute-v',
      );
      final positions = [
        for (final id in [a, b, c])
          Transform2.translation(
            result[id]!.x,
            result[id]!.y,
          ).mapBounds(bounds[id]!),
      ];
      if (horizontal) {
        expect(positions.first.left, -100);
        expect(positions.last.right, 100);
        expect(
          positions[1].left - positions[0].right,
          closeTo(positions[2].left - positions[1].right, 1e-9),
        );
      } else {
        expect(positions.first.top, -90);
        expect(positions.last.bottom, 110);
        expect(
          positions[1].top - positions[0].bottom,
          closeTo(positions[2].top - positions[1].bottom, 1e-9),
        );
      }
    }
    expect(selectionLayout({a: bounds[a]!}, 'align-left'), isEmpty);
    expect(
      selectionLayout({a: bounds[a]!, b: bounds[b]!}, 'distribute-h'),
      isEmpty,
    );
    expect(() => selectionLayout(bounds, 'unknown'), throwsArgumentError);
  });
}
