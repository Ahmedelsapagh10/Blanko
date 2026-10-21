import 'dart:math' as math;

import '../document/document.dart';
import '../document/document_geometry.dart';
import '../document/element.dart';
import '../geometry/geometry.dart';
import '../spatial/spatial_grid.dart';

/// Geometry and broad-phase lookup owned by one committed document snapshot.
/// Pointer previews and camera changes do not rebuild this scene.
final class EditorScene {
  EditorScene(this.document) : _geometry = DocumentGeometry(document) {
    final order = <DocumentElement>[];
    for (final element in document.preorder) {
      final parent = element.parentId;
      _locked[element.id] = element.locked || (_locked[parent] ?? false);
      _hidden[element.id] = element.opacity == 0 || (_hidden[parent] ?? false);
      final local = _localBounds(element.content);
      if (local != null) {
        _bounds[element.id] = worldTransformOf(element.id).mapBounds(local);
        if (!_hidden[element.id]!) order.add(element);
      }
    }
    // Groups have no painted rectangle, but their selection extent is useful to
    // callers inspecting an existing hierarchy. Descendants remain paint targets.
    for (final element in document.preorder.reversed) {
      final bounds = _bounds[element.id];
      var parent = element.parentId;
      while (bounds != null && parent != null) {
        final owner = document.byId[parent]!;
        if (owner.content is GroupElementContent) {
          _bounds[parent] = _union(_bounds[parent], bounds);
        }
        parent = owner.parentId;
      }
    }
    paintOrder = List.unmodifiable(order);
    _index = SpatialGrid(order.map((element) => _bounds[element.id]!));
  }

  final BoardDocument document;
  final DocumentGeometry _geometry;
  final _bounds = <ElementId, Bounds2>{};
  final _locked = <ElementId, bool>{};
  final _hidden = <ElementId, bool>{};
  late final List<DocumentElement> paintOrder;
  late final SpatialGrid _index;

  Transform2 worldTransformOf(ElementId id) => _geometry.worldTransformOf(id);

  Bounds2 boundsOf(ElementId id) {
    final bounds = _bounds[id];
    if (bounds != null) return bounds;
    // An empty group still has a valid position, but no painted area.
    final origin = worldTransformOf(id).apply(Point2.zero);
    return Bounds2(origin.x, origin.y, origin.x, origin.y);
  }

  List<DocumentElement> visible(Bounds2 worldViewport) => [
    for (final index in _index.query(worldViewport)) paintOrder[index],
  ];

  bool isLocked(ElementId id) => _locked[id] ?? true;

  bool belongsTo(ElementId id, ElementId ancestor) {
    ElementId? current = id;
    while (current != null) {
      if (current == ancestor) return true;
      current = document.byId[current]?.parentId;
    }
    return false;
  }

  Iterable<ElementId> eraserHits(Point2 world, double radius) sync* {
    final area = Bounds2(world.x, world.y, world.x, world.y).inflate(radius);
    for (final index in _index.query(area)) {
      final element = paintOrder[index];
      if (isLocked(element.id)) continue;
      final local = _geometry.worldToLocal(element.id, world);
      final tolerance =
          radius * worldTransformOf(element.id).inverse().maximumScale;
      if (_hits(element.content, local, tolerance)) yield element.id;
    }
  }

  ElementId? hitTest(
    Point2 world, {
    required double worldTolerance,
    bool includeLocked = false,
  }) {
    if (!worldTolerance.isFinite || worldTolerance < 0) {
      throw ArgumentError.value(worldTolerance, 'worldTolerance');
    }
    final area = Bounds2(
      world.x,
      world.y,
      world.x,
      world.y,
    ).inflate(worldTolerance);
    for (final index in _index.query(area).reversed) {
      final element = paintOrder[index];
      if (!includeLocked && _locked[element.id]!) continue;
      final local = _geometry.worldToLocal(element.id, world);
      // Exact for similarity transforms; conservative for non-uniform scale or
      // shear so a thin transformed stroke remains accessible with the mouse.
      final tolerance =
          worldTolerance * worldTransformOf(element.id).inverse().maximumScale;
      if (_hits(element.content, local, tolerance)) return element.id;
    }
    return null;
  }
}

Bounds2? _localBounds(ElementContent content) => switch (content) {
  ShapeElementContent(:final bounds, :final stroke) => bounds.inflate(
    stroke?.width == null ? 0 : stroke!.width / 2,
  ),
  StrokeElementContent(:final points, :final style) => Bounds2.fromPoints(
    points,
  ).inflate(style.width / 2),
  LineElementContent(:final start, :final end, :final style) =>
    Bounds2.fromPoints([start, end]).inflate(style.width / 2),
  ArrowElementContent(
    :final start,
    :final end,
    :final style,
    :final headLength,
    :final headWidth,
  ) =>
    Bounds2.fromPoints([
      start,
      end,
    ]).inflate(math.max(style.width / 2, math.max(headLength, headWidth))),
  TextElementContent(:final bounds) => bounds,
  StickyNoteElementContent(:final bounds) => bounds,
  ImageElementContent(:final bounds) => bounds,
  ExportFrameElementContent(:final bounds) => bounds,
  ContainerFrameElementContent(:final bounds) => bounds,
  GroupElementContent() => null,
};

Bounds2 _union(Bounds2? first, Bounds2 second) => first == null
    ? second
    : Bounds2(
        math.min(first.left, second.left),
        math.min(first.top, second.top),
        math.max(first.right, second.right),
        math.max(first.bottom, second.bottom),
      );

bool _visibleColor(int? color) => color != null && (color >> 24) != 0;

bool _hits(ElementContent content, Point2 point, double tolerance) {
  switch (content) {
    case ShapeElementContent():
      final bounds = content.bounds;
      final vertices = content.kind == ShapeKind.triangle
          ? [
              Point2(bounds.center.x, bounds.top),
              Point2(bounds.right, bounds.bottom),
              Point2(bounds.left, bounds.bottom),
            ]
          : [
              Point2(bounds.left, bounds.top),
              Point2(bounds.right, bounds.top),
              Point2(bounds.right, bounds.bottom),
              Point2(bounds.left, bounds.bottom),
            ];
      final inside = switch (content.kind) {
        ShapeKind.rectangle => bounds.contains(point),
        ShapeKind.triangle => _insideTriangle(point, vertices),
        ShapeKind.ellipse => _insideEllipse(point, bounds),
      };
      if (_visibleColor(content.fillColor) && inside) return true;
      final stroke = content.stroke;
      final radius = stroke != null && _visibleColor(stroke.color)
          ? stroke.width / 2
          : 0.0;
      if (!_visibleColor(content.fillColor) && radius == 0) return false;
      final distance = content.kind == ShapeKind.ellipse
          ? _ellipseBoundaryDistance(point, bounds)
          : _polylineDistance(point, [...vertices, vertices.first]);
      return distance <= radius + tolerance;
    case StrokeElementContent():
      return _visibleColor(content.style.color) &&
          _polylineDistance(point, content.points) <=
              content.style.width / 2 + tolerance;
    case LineElementContent():
      return _visibleColor(content.style.color) &&
          _segmentDistance(point, content.start, content.end) <=
              content.style.width / 2 + tolerance;
    case ArrowElementContent():
      // The first slice creates lines, not arrows; existing arrow bounds are
      // retained conservatively until arrowhead editing is implemented.
      return _visibleColor(content.style.color) &&
          _localBounds(content)!.inflate(tolerance).contains(point);
    case GroupElementContent():
      return false;
    case ContainerFrameElementContent(:final bounds):
    case ExportFrameElementContent(:final bounds):
      return bounds.inflate(tolerance).contains(point) &&
          ((point.x - bounds.left).abs() <= tolerance ||
              (point.x - bounds.right).abs() <= tolerance ||
              (point.y - bounds.top).abs() <= tolerance ||
              (point.y - bounds.bottom).abs() <= tolerance);
    default:
      return _localBounds(content)!.inflate(tolerance).contains(point);
  }
}

double _polylineDistance(Point2 point, List<Point2> points) {
  if (points.length == 1) return point.distanceTo(points.single);
  var distance = double.infinity;
  for (var i = 1; i < points.length; i++) {
    distance = math.min(
      distance,
      _segmentDistance(point, points[i - 1], points[i]),
    );
  }
  return distance;
}

double _segmentDistance(Point2 point, Point2 start, Point2 end) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return point.distanceTo(start);
  final projection =
      (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
          .clamp(0.0, 1.0);
  return point.distanceTo(
    Point2(start.x + dx * projection, start.y + dy * projection),
  );
}

bool _insideTriangle(Point2 point, List<Point2> vertices) {
  double cross(Point2 a, Point2 b) =>
      (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x);
  final a = cross(vertices[0], vertices[1]);
  final b = cross(vertices[1], vertices[2]);
  final c = cross(vertices[2], vertices[0]);
  return !((a < 0 || b < 0 || c < 0) && (a > 0 || b > 0 || c > 0));
}

bool _insideEllipse(Point2 point, Bounds2 bounds) {
  final x = (point.x - bounds.center.x) / (bounds.width / 2);
  final y = (point.y - bounds.center.y) / (bounds.height / 2);
  return x * x + y * y <= 1;
}

// Search one quadrant for the nearest point on the actual ellipse. This is
// evaluated only for a broad-phase hit candidate, never during painting.
double _ellipseBoundaryDistance(Point2 point, Bounds2 bounds) {
  final x = (point.x - bounds.center.x).abs();
  final y = (point.y - bounds.center.y).abs();
  final rx = bounds.width / 2;
  final ry = bounds.height / 2;
  double squared(double angle) {
    final dx = rx * math.cos(angle) - x;
    final dy = ry * math.sin(angle) - y;
    return dx * dx + dy * dy;
  }

  const steps = 32;
  final step = math.pi / 2 / steps;
  var best = 0;
  var value = squared(0);
  for (var i = 1; i <= steps; i++) {
    final candidate = squared(i * step);
    if (candidate < value) {
      best = i;
      value = candidate;
    }
  }
  var left = math.max(0, best - 1) * step;
  var right = math.min(steps, best + 1) * step;
  for (var i = 0; i < 40; i++) {
    final first = left + (right - left) / 3;
    final second = right - (right - left) / 3;
    if (squared(first) < squared(second)) {
      right = second;
    } else {
      left = first;
    }
  }
  return math.sqrt(math.min(value, squared((left + right) / 2)));
}
