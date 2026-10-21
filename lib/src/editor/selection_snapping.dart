import 'dart:math' as math;

import '../document/element.dart';
import '../geometry/geometry.dart';

final class SnapGuide {
  const SnapGuide({
    required this.vertical,
    required this.position,
    required this.start,
    required this.end,
  });
  final bool vertical;
  final double position;
  final double start;
  final double end;
}

final class SnapResult {
  SnapResult(this.delta, Iterable<SnapGuide> guides)
    : guides = List.unmodifiable(guides);
  final Point2 delta;
  final List<SnapGuide> guides;
}

/// Candidates come from the editor's spatial query; this helper owns no cache.
/// Tolerance is world-space (for example 6 / camera.zoom for a six-pixel snap).
SnapResult snapMove({
  required Bounds2 movingBounds,
  required Point2 delta,
  required Iterable<Bounds2> candidates,
  required double tolerance,
  double? gridSpacing,
}) {
  if (!tolerance.isFinite || tolerance < 0) {
    throw ArgumentError.value(tolerance, 'tolerance');
  }
  if (gridSpacing != null && (!gridSpacing.isFinite || gridSpacing <= 0)) {
    throw ArgumentError.value(gridSpacing, 'gridSpacing');
  }
  final moved = _translated(movingBounds, delta);
  _AxisSnap? xSnap, ySnap;
  for (final candidate in candidates.take(128)) {
    xSnap = _nearest(
      xSnap,
      [moved.left, moved.center.x, moved.right],
      [candidate.left, candidate.center.x, candidate.right],
      tolerance,
      candidate,
    );
    ySnap = _nearest(
      ySnap,
      [moved.top, moved.center.y, moved.bottom],
      [candidate.top, candidate.center.y, candidate.bottom],
      tolerance,
      candidate,
    );
  }
  if (gridSpacing != null) {
    // Snap the moving selection's leading corner to a grid intersection.
    // Existing object alignment wins an equal-distance tie.
    xSnap = _grid(xSnap, moved.left, gridSpacing, tolerance);
    ySnap = _grid(ySnap, moved.top, gridSpacing, tolerance);
  }
  final snapped = _translated(
    moved,
    Point2(xSnap?.correction ?? 0, ySnap?.correction ?? 0),
  );
  final guides = <SnapGuide>[];
  if (xSnap != null) {
    final target = xSnap.target;
    guides.add(
      SnapGuide(
        vertical: true,
        position: xSnap.position,
        start: math.min(snapped.top, target?.top ?? snapped.top),
        end: math.max(snapped.bottom, target?.bottom ?? snapped.bottom),
      ),
    );
  }
  if (ySnap != null) {
    final target = ySnap.target;
    guides.add(
      SnapGuide(
        vertical: false,
        position: ySnap.position,
        start: math.min(snapped.left, target?.left ?? snapped.left),
        end: math.max(snapped.right, target?.right ?? snapped.right),
      ),
    );
  }
  return SnapResult(
    Point2(
      delta.x + (xSnap?.correction ?? 0),
      delta.y + (ySnap?.correction ?? 0),
    ),
    guides,
  );
}

final class _AxisSnap {
  const _AxisSnap(this.correction, this.position, this.target);
  final double correction;
  final double position;
  final Bounds2? target;
}

_AxisSnap? _nearest(
  _AxisSnap? current,
  List<double> sources,
  List<double> targets,
  double tolerance,
  Bounds2 candidate,
) {
  for (final source in sources) {
    for (final target in targets) {
      final correction = target - source;
      final distance = correction.abs();
      if (distance > tolerance) continue;
      if (current == null ||
          distance < current.correction.abs() ||
          (distance == current.correction.abs() &&
              (target < current.position ||
                  (target == current.position &&
                      (correction < current.correction ||
                          (correction == current.correction &&
                              _compareBounds(candidate, current.target!) <
                                  0)))))) {
        current = _AxisSnap(correction, target, candidate);
      }
    }
  }
  return current;
}

int _compareBounds(Bounds2 first, Bounds2 second) {
  final a = [first.left, first.top, first.right, first.bottom];
  final b = [second.left, second.top, second.right, second.bottom];
  for (var i = 0; i < a.length; i++) {
    final order = a[i].compareTo(b[i]);
    if (order != 0) return order;
  }
  return 0;
}

_AxisSnap? _grid(
  _AxisSnap? current,
  double coordinate,
  double spacing,
  double tolerance,
) {
  final cell = coordinate / spacing;
  if (!cell.isFinite) return current;
  final target = cell.roundToDouble() * spacing;
  final correction = target - coordinate;
  if (correction.abs() <= tolerance &&
      (current == null || correction.abs() < current.correction.abs())) {
    return _AxisSnap(correction, target, null);
  }
  return current;
}

Bounds2 _translated(Bounds2 bounds, Point2 delta) => Bounds2(
  bounds.left + delta.x,
  bounds.top + delta.y,
  bounds.right + delta.x,
  bounds.bottom + delta.y,
);

/// Uses transformed visual bounds supplied by the scene. No element is resized.
/// Distribution preserves the outer extent and equalizes gaps, including when
/// the available space requires overlapping objects.
Map<ElementId, Point2> selectionLayout(
  Map<ElementId, Bounds2> bounds,
  String action,
) {
  const alignments = {
    'align-left',
    'hcenter',
    'right',
    'top',
    'vcenter',
    'bottom',
  };
  final horizontalDistribution = action == 'distribute-h';
  final distribution = horizontalDistribution || action == 'distribute-v';
  if (!distribution && !alignments.contains(action)) {
    throw ArgumentError.value(action, 'action', 'Unknown selection layout.');
  }
  if (bounds.length < (distribution ? 3 : 2)) return const {};
  final extent = Bounds2.fromPoints([
    for (final b in bounds.values) ...[
      Point2(b.left, b.top),
      Point2(b.right, b.bottom),
    ],
  ]);
  if (!distribution) {
    return {
      for (final entry in bounds.entries)
        entry.key: switch (action) {
          'align-left' => Point2(extent.left - entry.value.left, 0),
          'hcenter' => Point2(extent.center.x - entry.value.center.x, 0),
          'right' => Point2(extent.right - entry.value.right, 0),
          'top' => Point2(0, extent.top - entry.value.top),
          'vcenter' => Point2(0, extent.center.y - entry.value.center.y),
          'bottom' => Point2(0, extent.bottom - entry.value.bottom),
          _ => throw StateError('Unreachable selection alignment.'),
        },
    };
  }
  final entries = bounds.entries.toList()
    ..sort((a, b) {
      final difference = horizontalDistribution
          ? a.value.center.x.compareTo(b.value.center.x)
          : a.value.center.y.compareTo(b.value.center.y);
      return difference != 0 ? difference : a.key.value.compareTo(b.key.value);
    });
  final totalSize = entries.fold<double>(
    0,
    (sum, entry) =>
        sum + (horizontalDistribution ? entry.value.width : entry.value.height),
  );
  final available = horizontalDistribution ? extent.width : extent.height;
  final gap = (available - totalSize) / (entries.length - 1);
  var cursor = horizontalDistribution ? extent.left : extent.top;
  final offsets = <ElementId, Point2>{};
  for (final entry in entries) {
    final b = entry.value;
    offsets[entry.key] = horizontalDistribution
        ? Point2(cursor - b.left, 0)
        : Point2(0, cursor - b.top);
    cursor += (horizontalDistribution ? b.width : b.height) + gap;
  }
  return offsets;
}
