import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/stroke_sampling.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

List<Point2> sample(List<Point2> input, {double tolerance = .75}) {
  final sampler = StrokeSampler(tolerance: tolerance);
  return [
    for (final point in input) ...sampler.add(point),
    ...sampler.finish(input.last),
  ];
}

void main() {
  test(
    'preserves first and true last points, including tiny final movement',
    () {
      final sampler = StrokeSampler(tolerance: .75);
      expect(sampler.add(Point2.zero), [Point2.zero]);
      expect(sampler.add(Point2(.1, .1)), isEmpty);
      expect(sampler.add(Point2.zero), isEmpty);
      final tail = sampler.finish(Point2(.2, .1));
      expect(tail.last, Point2(.2, .1));
      expect(tail.where((point) => point == Point2(.2, .1)), hasLength(1));
      expect(sampler.finish(Point2(.2, .1)), isEmpty);
      expect(() => sampler.add(Point2(1, 1)), throwsStateError);
      expect(StrokeSampler(tolerance: 1).finish(Point2.zero), [Point2.zero]);
    },
  );

  test('stationary input stays a single point and validates tolerance', () {
    expect(sample(List.filled(100, Point2.zero)), [Point2.zero]);
    for (final tolerance in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => StrokeSampler(tolerance: tolerance), throwsArgumentError);
    }
  });

  test(
    'smooths gentle curves deterministically without changing emitted lists',
    () {
      final input = [
        for (var i = 0; i < 100; i++) Point2(i * 2, math.sin(i / 12) * 8),
      ];
      final first = sample(input), second = sample(input);
      expect(first, second);
      expect(first.first, input.first);
      expect(first.last, input.last);
      expect(first.every((p) => p.x.isFinite && p.y.isFinite), isTrue);
      expect(first, isNot(orderedEquals(input)));
      final sampler = StrokeSampler(tolerance: .75);
      final emitted = sampler.add(Point2.zero);
      sampler.add(Point2(10, 1));
      sampler.finish(Point2(20, 2));
      expect(emitted, [Point2.zero]);
    },
  );

  test('sharp handwriting corners and reversals retain actual vertices', () {
    final input = [Point2.zero, Point2(20, 0), Point2(20, 20), Point2(20, 0)];
    final output = sample(input);
    for (final point in input) {
      expect(output, contains(point));
    }
    expect(output.last, input.last);
  });

  test(
    'slow and fast straight paths preserve line, endpoints, and direction',
    () {
      for (final step in [.05, 20.0]) {
        final input = [
          for (var i = 0; i < 1000; i++) Point2(i * step, -i * step),
        ];
        final output = sample(input);
        expect(output.first, input.first);
        expect(output.last, input.last);
        for (var i = 1; i < output.length; i++) {
          expect(output[i].x, greaterThan(output[i - 1].x));
          expect(output[i].y, closeTo(-output[i].x, 1e-8));
        }
      }
    },
  );

  test('zoom-scaled tolerance retains the same screen-space geometry', () {
    final input = [
      for (var i = 0; i < 100; i++) Point2(i * .3, math.sin(i / 10)),
    ];
    final screen = sample(input);
    for (final zoom in [.05, 2.0, 32.0]) {
      final world = sample([
        for (final p in input) p * (1 / zoom),
      ], tolerance: .75 / zoom);
      expect(world, hasLength(screen.length));
      for (var i = 0; i < world.length; i++) {
        expect(world[i].x * zoom, closeTo(screen[i].x, 1e-8));
        expect(world[i].y * zoom, closeTo(screen[i].y, 1e-8));
      }
    }
    expect(
      sample(input, tolerance: .1).length,
      greaterThan(sample(input, tolerance: 2).length),
    );
  });

  test('abandoned samplers do not affect new strokes or saved polylines', () {
    final saved = List<Point2>.unmodifiable([Point2.zero, Point2(5, 5)]);
    final abandoned = StrokeSampler(tolerance: .75);
    for (final point in saved) {
      abandoned.add(point);
    }
    final input = [Point2(100, 200), Point2(120, 201), Point2(140, 205)];
    expect(sample(input), sample(input));
    expect(saved, [Point2.zero, Point2(5, 5)]);
  });

  test(
    'each event has bounded output even for sparse extreme finite inputs',
    () {
      final sampler = StrokeSampler(tolerance: .0001);
      final input = [Point2(-1e308, 0), Point2.zero, Point2(1e308, 1e307)];
      for (final point in input) {
        final result = sampler.add(point);
        expect(result.length, lessThanOrEqualTo(32));
        expect(result.every((p) => p.x.isFinite && p.y.isFinite), isTrue);
      }
      expect(sampler.finish(input.last).last, input.last);
    },
  );
}
