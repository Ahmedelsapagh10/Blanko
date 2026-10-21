import 'dart:math' as math;

import '../geometry/geometry.dart';

/// Incremental world-space polyline sampling; emitted points never change.
/// Use a screen-space tolerance divided by camera zoom. The caller owns the
/// accumulated stroke and its total sample limit; this sampler retains 3 points.
final class StrokeSampler {
  StrokeSampler({required this.tolerance}) {
    if (!tolerance.isFinite || tolerance <= 0) {
      throw ArgumentError.value(tolerance, 'tolerance');
    }
  }

  final double tolerance;
  Point2? _before;
  Point2? _last;
  Point2? _emitted;
  bool _finished = false;

  /// Returns only newly stable samples, with at most 32 points per call.
  List<Point2> add(Point2 point) {
    if (_finished) throw StateError('Stroke sampling has finished.');
    return _accept(point, force: false);
  }

  /// Flushes the true endpoint, even when it is below the sampling tolerance.
  /// Repeated finish calls are harmless; create a new sampler for a new stroke.
  List<Point2> finish(Point2 point) {
    if (_finished) return const [];
    final result = _accept(point, force: true);
    _append(result, point);
    _finished = true;
    return result;
  }

  List<Point2> _accept(Point2 point, {required bool force}) {
    final result = <Point2>[];
    final last = _last;
    if (last == null) {
      _last = point;
      _append(result, point);
      return result;
    }
    if (last == point || (!force && _distance(last, point) < tolerance)) {
      return result;
    }
    final midpoint = _midpoint(last, point);
    final before = _before;
    if (before == null) {
      _append(result, midpoint);
    } else if (_isCorner(before, last, point)) {
      // Preserve vertices at turns of 60 degrees or more, including reversals.
      _append(result, last);
      _append(result, midpoint);
    } else {
      final start = _emitted!;
      final deviation = _distance(last, _midpoint(start, midpoint));
      final flatness = tolerance * (2 / 3);
      // Quadratic chord error is deviation / (2 * subdivisions squared).
      // Cap extreme sparse input work rather than allocating unbounded samples.
      final count = deviation >= flatness * 2048
          ? 32
          : math.max(1, math.sqrt(deviation / flatness / 2).ceil());
      for (var index = 1; index <= count; index++) {
        final t = index / count;
        _append(
          result,
          _lerp(_lerp(start, last, t), _lerp(last, midpoint, t), t),
        );
      }
    }
    _before = last;
    _last = point;
    return result;
  }

  void _append(List<Point2> result, Point2 point) {
    if (_emitted != point) {
      result.add(point);
      _emitted = point;
    }
  }
}

Point2 _midpoint(Point2 a, Point2 b) =>
    Point2(a.x / 2 + b.x / 2, a.y / 2 + b.y / 2);

Point2 _lerp(Point2 a, Point2 b, double t) =>
    Point2(a.x * (1 - t) + b.x * t, a.y * (1 - t) + b.y * t);

double _distance(Point2 a, Point2 b) {
  final dx = (a.x / 2 - b.x / 2).abs();
  final dy = (a.y / 2 - b.y / 2).abs();
  final scale = math.max(dx, dy);
  if (scale == 0) return 0;
  return scale *
      math.sqrt((dx / scale) * (dx / scale) + (dy / scale) * (dy / scale)) *
      2;
}

bool _isCorner(Point2 a, Point2 b, Point2 c) {
  final ax = b.x / 2 - a.x / 2, ay = b.y / 2 - a.y / 2;
  final bx = c.x / 2 - b.x / 2, by = c.y / 2 - b.y / 2;
  final scaleA = math.max(ax.abs(), ay.abs());
  final scaleB = math.max(bx.abs(), by.abs());
  if (scaleA == 0 || scaleB == 0) return false;
  final ux = ax / scaleA, uy = ay / scaleA;
  final vx = bx / scaleB, vy = by / scaleB;
  return ux * vx + uy * vy <=
      .5 * math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
}
