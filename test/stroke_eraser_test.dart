import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/stroke_eraser.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

void main() {
  List<List<Point2>> erase(
    List<Point2> points, {
    Point2? from,
    Point2? to,
    double radius = 2,
    Transform2 transform = Transform2.identity,
  }) => eraseStrokeSegment(
    points: points,
    worldTransform: transform,
    from: from ?? Point2.zero,
    to: to ?? from ?? Point2.zero,
    radius: radius,
  );

  test(
    'fast crossing clips the capsule sides without sampled-pointer gaps',
    () {
      final result = erase(
        [Point2(-10, 0), Point2(10, 0)],
        from: Point2(0, -100),
        to: Point2(0, 100),
      );
      expect(result.length, 2);
      expect(result.first.last.x, closeTo(-2, 1e-10));
      expect(result.last.first.x, closeTo(2, 1e-10));
      expect(result.first.first, Point2(-10, 0));
      expect(result.last.last, Point2(10, 0));
    },
  );

  test(
    'multiple crossings preserve ordered fragments and intermediate points',
    () {
      final result = erase([
        Point2(-10, 0),
        Point2(0, 0),
        Point2(10, 0),
        Point2(0, 0),
        Point2(-10, 0),
      ]);
      expect(result.length, 3);
      expect(result[1], contains(Point2(10, 0)));
      expect(result[0].last.x, closeTo(-2, 1e-10));
      expect(result[1].first.x, closeTo(2, 1e-10));
      expect(result[1].last.x, closeTo(2, 1e-10));
    },
  );

  test('nonuniform rotation and translation return local coordinates', () {
    final transform =
        Transform2.translation(100, 50) *
        Transform2.rotation(math.pi / 2) *
        Transform2.scale(2, 3);
    final result = erase(
      [Point2(-10, 0), Point2(10, 0)],
      from: Point2(100, 50),
      transform: transform,
    );
    expect(result.length, 2);
    expect(result.first.last.x, closeTo(-1, 1e-10));
    expect(result.last.first.x, closeTo(1, 1e-10));
    expect(result.first.last.y, 0);
  });

  test('endpoint cap erasure leaves one surviving fragment', () {
    final result = erase([Point2.zero, Point2(10, 0)]);
    expect(result.length, 1);
    expect(result.single.first.x, closeTo(2, 1e-10));
    expect(result.single.last, Point2(10, 0));
  });

  test('small eraser remains precise on a billion-unit stroke', () {
    final result = erase([Point2(-1e9, 0), Point2(1e9, 0)]);
    expect(result.length, 2);
    expect(result.first.last.x, closeTo(-2, 1e-6));
    expect(result.last.first.x, closeTo(2, 1e-6));
  });

  test('dots are removed only inside the swept capsule', () {
    expect(erase([Point2.zero]), isEmpty);
    expect(erase([Point2(10, 0)]).single, [Point2(10, 0)]);
    expect(erase([Point2(0, 5)], to: Point2(0, 10)), isEmpty);
  });

  test('no-hit and tangent strokes retain original points', () {
    final noHit = [Point2(10, 10), Point2(20, 20)];
    final tangent = [Point2(-10, 2), Point2(10, 2)];
    expect(identical(erase(noHit).single, noHit), isTrue);
    expect(identical(erase(tangent).single, tangent), isTrue);
  });

  test(
    'entirely erased and duplicate points leave no degenerate fragments',
    () {
      expect(erase([Point2(-1, 0), Point2.zero, Point2(1, 0)]), isEmpty);
      expect(erase([Point2.zero, Point2.zero]), isEmpty);
    },
  );

  test('successive sweeps can clip an already split fragment', () {
    final first = erase([Point2(-10, 0), Point2(10, 0)]);
    final second = erase(first.last, from: Point2(7, 0), radius: 1);
    expect(second.length, 2);
    expect(second.first.first.x, closeTo(2, 1e-10));
    expect(second.first.last.x, closeTo(6, 1e-10));
    expect(second.last.first.x, closeTo(8, 1e-10));
    expect(second.last.last.x, 10);
  });
}
