import 'dart:math' as math;

import '../geometry/geometry.dart';

/// Clips a local polyline against the world-space capsule swept by an eraser.
/// The caller includes any desired stroke-width allowance in [radius].
List<List<Point2>> eraseStrokeSegment({
  required List<Point2> points,
  required Transform2 worldTransform,
  required Point2 from,
  required Point2 to,
  required double radius,
}) {
  if (!radius.isFinite || radius <= 0) {
    throw ArgumentError.value(radius, 'radius', 'Must be finite and positive.');
  }
  if (points.isEmpty) return [];
  final axis = to - from;
  final axisSquared = _dot(axis, axis);
  final radiusSquared = radius * radius;
  double distanceSquared(Point2 point) {
    final offset = point - from;
    final t = axisSquared == 0
        ? 0.0
        : (_dot(offset, axis) / axisSquared).clamp(0.0, 1.0);
    final delta = offset - axis * t;
    return _dot(delta, delta);
  }

  if (points.length == 1) {
    return distanceSquared(worldTransform.apply(points.single)) <= radiusSquared
        ? []
        : [points];
  }

  final fragments = <List<Point2>>[];
  var current = <Point2>[];
  var changed = false;
  void finish() {
    if (current.length > 1 &&
        current
            .skip(1)
            .any(
              (point) =>
                  worldTransform
                      .apply(point)
                      .distanceTo(worldTransform.apply(current.first)) >
                  1e-8,
            )) {
      fragments.add(current);
    }
    current = [];
  }

  for (var index = 1; index < points.length; index++) {
    final localStart = points[index - 1];
    final localEnd = points[index];
    final start = worldTransform.apply(localStart);
    final delta = worldTransform.apply(localEnd) - start;
    final lengthSquared = _dot(delta, delta);
    if (lengthSquared == 0) {
      if (distanceSquared(start) < radiusSquared) {
        changed = true;
        finish();
      }
      continue;
    }
    final cuts = <double>[0, 1];
    void addCut(double t) {
      if (t.isFinite && t > 0 && t < 1) cuts.add(t);
    }

    // End caps and the two parallel sides contain every capsule boundary.
    for (final center in [from, to]) {
      final offset = start - center;
      final closest = -_dot(offset, delta) / lengthSquared;
      final perpendicular = offset + delta * closest;
      final remaining = radiusSquared - _dot(perpendicular, perpendicular);
      if (remaining >= 0) {
        // Closest approach avoids subtracting two enormous squared distances
        // when a small eraser crosses a long stroke in a large world.
        final spread = math.sqrt(remaining / lengthSquared);
        addCut(closest - spread);
        addCut(closest + spread);
      }
    }
    if (axisSquared > 0) {
      final crossStart = _cross(start - from, axis);
      final crossDelta = _cross(delta, axis);
      if (crossDelta != 0) {
        final side = radius * math.sqrt(axisSquared);
        addCut((side - crossStart) / crossDelta);
        addCut((-side - crossStart) / crossDelta);
      }
    }
    cuts.sort();
    for (var cut = 1; cut < cuts.length; cut++) {
      final low = cuts[cut - 1];
      final high = cuts[cut];
      if (high <= low) continue;
      final midpoint = start + delta * ((low + high) / 2);
      if (distanceSquared(midpoint) < radiusSquared * (1 - 1e-12)) {
        changed = true;
        finish();
      } else {
        final a = localStart + (localEnd - localStart) * low;
        final b = localStart + (localEnd - localStart) * high;
        if (current.isEmpty) current.add(a);
        if (current.last != b) current.add(b);
      }
    }
  }
  if (!changed) return [points];
  finish();
  return fragments;
}

double _dot(Point2 a, Point2 b) => a.x * b.x + a.y * b.y;
double _cross(Point2 a, Point2 b) => a.x * b.y - a.y * b.x;
