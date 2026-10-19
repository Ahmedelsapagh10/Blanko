import 'dart:math' as math;

final class Point2 {
  factory Point2(double x, double y) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Coordinates must be finite.');
    }
    return Point2._(x, y);
  }

  const Point2._(this.x, this.y);
  static const zero = Point2._(0, 0);

  final double x;
  final double y;

  Point2 operator +(Point2 other) => Point2(x + other.x, y + other.y);
  Point2 operator -(Point2 other) => Point2(x - other.x, y - other.y);
  Point2 operator *(double factor) => Point2(x * factor, y * factor);

  double distanceTo(Point2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is Point2 && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

final class Bounds2 {
  factory Bounds2(double left, double top, double right, double bottom) {
    if (![left, top, right, bottom].every((value) => value.isFinite) ||
        right < left ||
        bottom < top ||
        !(right - left).isFinite ||
        !(bottom - top).isFinite) {
      throw ArgumentError('Bounds must be finite and ordered.');
    }
    return Bounds2._(left, top, right, bottom);
  }

  const Bounds2._(this.left, this.top, this.right, this.bottom);

  factory Bounds2.fromPoints(Iterable<Point2> points) {
    final iterator = points.iterator;
    if (!iterator.moveNext()) throw ArgumentError('Points cannot be empty.');
    var left = iterator.current.x;
    var right = left;
    var top = iterator.current.y;
    var bottom = top;
    while (iterator.moveNext()) {
      final point = iterator.current;
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    return Bounds2(left, top, right, bottom);
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  Point2 get center => Point2(left + width / 2, top + height / 2);

  bool contains(Point2 point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  bool intersects(Bounds2 other) =>
      left <= other.right &&
      right >= other.left &&
      top <= other.bottom &&
      bottom >= other.top;

  Bounds2 inflate(double amount) {
    if (!amount.isFinite || amount < 0) {
      throw ArgumentError.value(amount, 'amount');
    }
    return Bounds2(
      left - amount,
      top - amount,
      right + amount,
      bottom + amount,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Bounds2 &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// Column-vector affine transform: [a c tx; b d ty; 0 0 1].
/// Keeping all six coefficients preserves shear during nested reparenting.
final class Transform2 {
  factory Transform2({
    double a = 1,
    double b = 0,
    double c = 0,
    double d = 1,
    double tx = 0,
    double ty = 0,
  }) {
    final determinant = a * d - b * c;
    if (![a, b, c, d, tx, ty, determinant].every((value) => value.isFinite) ||
        determinant == 0) {
      throw ArgumentError('Transform must be finite and invertible.');
    }
    if (![
      d / determinant,
      -b / determinant,
      -c / determinant,
      a / determinant,
      (c * ty - d * tx) / determinant,
      (b * tx - a * ty) / determinant,
    ].every((value) => value.isFinite)) {
      throw ArgumentError('Inverse transform must be finite.');
    }
    return Transform2._(a, b, c, d, tx, ty);
  }

  const Transform2._(this.a, this.b, this.c, this.d, this.tx, this.ty);
  static const identity = Transform2._(1, 0, 0, 1, 0, 0);

  factory Transform2.translation(double x, double y) =>
      Transform2(tx: x, ty: y);

  factory Transform2.rotation(double radians) => Transform2(
    a: math.cos(radians),
    b: math.sin(radians),
    c: -math.sin(radians),
    d: math.cos(radians),
  );

  factory Transform2.scale(double x, double y) => Transform2(a: x, d: y);

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;

  @override
  bool operator ==(Object other) =>
      other is Transform2 &&
      a == other.a &&
      b == other.b &&
      c == other.c &&
      d == other.d &&
      tx == other.tx &&
      ty == other.ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  double get maximumScale {
    final scale = [a.abs(), b.abs(), c.abs(), d.abs()].reduce(math.max);
    final aa = a / scale;
    final bb = b / scale;
    final cc = c / scale;
    final dd = d / scale;
    final trace = aa * aa + bb * bb + cc * cc + dd * dd;
    final determinant = aa * dd - bb * cc;
    return scale *
        math.sqrt(
          (trace +
                  math.sqrt(
                    math.max(0, trace * trace - 4 * determinant * determinant),
                  )) /
              2,
        );
  }

  Point2 apply(Point2 point) =>
      Point2(a * point.x + c * point.y + tx, b * point.x + d * point.y + ty);

  /// Applies [other] first, then this transform.
  Transform2 operator *(Transform2 other) => Transform2(
    a: a * other.a + c * other.b,
    b: b * other.a + d * other.b,
    c: a * other.c + c * other.d,
    d: b * other.c + d * other.d,
    tx: a * other.tx + c * other.ty + tx,
    ty: b * other.tx + d * other.ty + ty,
  );

  Transform2 inverse() {
    final determinant = a * d - b * c;
    return Transform2(
      a: d / determinant,
      b: -b / determinant,
      c: -c / determinant,
      d: a / determinant,
      tx: (c * ty - d * tx) / determinant,
      ty: (b * tx - a * ty) / determinant,
    );
  }

  Bounds2 mapBounds(Bounds2 bounds) => Bounds2.fromPoints([
    apply(Point2(bounds.left, bounds.top)),
    apply(Point2(bounds.right, bounds.top)),
    apply(Point2(bounds.right, bounds.bottom)),
    apply(Point2(bounds.left, bounds.bottom)),
  ]);

  /// Local transform under [newParentWorld], preserving the world transform.
  Transform2 relativeTo(Transform2 newParentWorld) =>
      newParentWorld.inverse() * this;
}
