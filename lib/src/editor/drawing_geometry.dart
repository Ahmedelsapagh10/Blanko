import 'dart:math' as math;

import '../document/element.dart';
import '../geometry/geometry.dart';

typedef DrawingSegment = ({Point2 start, Point2 end});

/// The exact shaft and wings shared by artwork, culling and picking.
List<DrawingSegment> arrowSegments(ArrowElementContent arrow) {
  final start = arrow.start, end = arrow.end;
  final length = start.distanceTo(end);
  final dx = (end.x - start.x) / length;
  final dy = (end.y - start.y) / length;
  final available = arrow.heads == ArrowHeadStyle.both ? length / 2 : length;
  final headLength = math.min(arrow.headLength, available);
  final halfWidth = arrow.headWidth / 2 * (headLength / arrow.headLength);
  final result = <DrawingSegment>[(start: start, end: end)];
  void head(Point2 tip, double direction) {
    final baseX = tip.x - direction * dx * headLength;
    final baseY = tip.y - direction * dy * headLength;
    result.addAll([
      (start: Point2(baseX - dy * halfWidth, baseY + dx * halfWidth), end: tip),
      (start: tip, end: Point2(baseX + dy * halfWidth, baseY - dx * halfWidth)),
    ]);
  }

  if (arrow.heads == ArrowHeadStyle.start ||
      arrow.heads == ArrowHeadStyle.both) {
    head(start, -1);
  }
  if (arrow.heads == ArrowHeadStyle.end || arrow.heads == ArrowHeadStyle.both) {
    head(end, 1);
  }
  return result;
}

Bounds2 arrowBounds(ArrowElementContent arrow) => Bounds2.fromPoints([
  for (final segment in arrowSegments(arrow)) ...[segment.start, segment.end],
]).inflate(arrow.style.width / 2);

double drawingSegmentDistance(Point2 point, Point2 start, Point2 end) {
  final dx = end.x - start.x, dy = end.y - start.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return point.distanceTo(start);
  final t =
      (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
          .clamp(0.0, 1.0);
  return point.distanceTo(Point2(start.x + dx * t, start.y + dy * t));
}

bool arrowHits(ArrowElementContent arrow, Point2 point, double tolerance) =>
    arrowSegments(arrow).any(
      (segment) =>
          drawingSegmentDistance(point, segment.start, segment.end) <=
          arrow.style.width / 2 + tolerance,
    );
