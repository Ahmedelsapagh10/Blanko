import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../document/element.dart';
import '../geometry/geometry.dart';
import 'drawing_geometry.dart';
import 'editor_text.dart';

Rect artworkRect(Bounds2 bounds) =>
    Rect.fromLTRB(bounds.left, bounds.top, bounds.right, bounds.bottom);

/// Local paths shared by the editor and offscreen output. No canvas chrome.
Path artworkPath(ElementContent content) {
  final path = Path();
  switch (content) {
    case ShapeElementContent(:final kind, :final bounds):
      switch (kind) {
        case ShapeKind.rectangle:
          path.addRect(artworkRect(bounds));
        case ShapeKind.ellipse:
          path.addOval(artworkRect(bounds));
        case ShapeKind.triangle:
          path
            ..moveTo(bounds.center.x, bounds.top)
            ..lineTo(bounds.right, bounds.bottom)
            ..lineTo(bounds.left, bounds.bottom)
            ..close();
      }
    case StrokeElementContent(:final points):
      path.moveTo(points.first.x, points.first.y);
      for (final point in points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
    case LineElementContent(:final start, :final end):
      path
        ..moveTo(start.x, start.y)
        ..lineTo(end.x, end.y);
    case ArrowElementContent():
      for (final segment in arrowSegments(content)) {
        path
          ..moveTo(segment.start.x, segment.start.y)
          ..lineTo(segment.end.x, segment.end.y);
      }
    default:
      break;
  }
  return path;
}

/// Deterministic local distances: four stroke widths on, two off.
Path dashedArtworkPath(Path source, double width) {
  final result = Path();
  final metrics = source.computeMetrics().toList(growable: false);
  final length = metrics.fold(0.0, (sum, metric) => sum + metric.length);
  // Coarsen only extreme paths; never allocate millions of tiny dash pieces.
  final period = math.max(width * 6, length / 4096);
  final dash = period * (2 / 3);
  for (final metric in metrics) {
    for (var distance = 0.0; distance < metric.length; distance += period) {
      result.addPath(
        metric.extractPath(distance, (distance + dash).clamp(0, metric.length)),
        Offset.zero,
      );
    }
  }
  return result;
}

/// Paints one element in its local space. The caller owns all supplied resources
/// and applies transforms, ancestor clipping and inherited opacity.
void paintElementArtwork(
  Canvas canvas,
  DocumentElement element, {
  Path? path,
  ElementTextLayout? textLayout,
  ui.Image? image,
  double? opacity,
}) {
  final content = element.content;
  final alpha = opacity ?? element.opacity;
  if (alpha <= 0) return;
  if (content is ImageElementContent) {
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      artworkRect(content.bounds),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: alpha),
    );
    return;
  }
  if (content is TextElementContent || content is StickyNoteElementContent) {
    final bounds = switch (content) {
      TextElementContent() => content.bounds,
      StickyNoteElementContent() => content.bounds,
      _ => throw StateError('Expected text.'),
    };
    final rect = artworkRect(bounds);
    canvas.saveLayer(
      rect,
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
    canvas.clipRect(rect);
    if (content is StickyNoteElementContent) {
      canvas.drawRect(rect, Paint()..color = Color(content.backgroundColor));
    }
    final padding = content is StickyNoteElementContent ? 12.0 : 0.0;
    textLayout?.paint(
      canvas,
      Offset(bounds.left + padding, bounds.top + padding),
    );
    canvas.restore();
    return;
  }
  final shapePath = path ?? artworkPath(content);
  if (content is ShapeElementContent && content.fillColor != null) {
    final color = Color(content.fillColor!);
    canvas.drawPath(
      shapePath,
      Paint()..color = color.withValues(alpha: color.a * alpha),
    );
  }
  final style = switch (content) {
    ShapeElementContent(:final stroke) => stroke,
    StrokeElementContent(:final style) => style,
    LineElementContent(:final style) => style,
    ArrowElementContent(:final style) => style,
    _ => null,
  };
  if (style == null) return;
  if (content is StrokeElementContent) {
    final highlighter = content.kind == StrokeKind.highlighter;
    paintFreehandPath(
      canvas,
      shapePath,
      style: style,
      opacity: alpha * (highlighter ? (content.highlighterOpacity ?? .28) : 1),
      highlighter: highlighter,
      dot: content.points.length == 1 ? content.points.single : null,
    );
    return;
  }
  canvas.drawPath(
    style.dashed ? dashedArtworkPath(shapePath, style.width) : shapePath,
    Paint()
      ..color = Color(
        style.color,
      ).withValues(alpha: Color(style.color).a * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}

/// Preview and committed strokes share one opacity/compositing implementation.
/// For highlighters, [opacity] includes the configured highlighter strength.
void paintFreehandPath(
  Canvas canvas,
  Path path, {
  required StrokeStyle style,
  double opacity = 1,
  bool highlighter = false,
  Point2? dot,
  Path? tail,
}) {
  if (opacity <= 0) return;
  final color = Color(style.color);
  final layered = highlighter || color.a * opacity < 1;
  final paint = Paint()
    ..color = color.withValues(alpha: layered ? 1 : color.a * opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = style.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  if (layered) {
    var extent = dot == null
        ? path.getBounds()
        : Rect.fromLTWH(dot.x, dot.y, 0, 0);
    if (tail != null) extent = extent.expandToInclude(tail.getBounds());
    canvas.saveLayer(
      extent.inflate(style.width / 2 + 1),
      Paint()..color = Colors.white.withValues(alpha: color.a * opacity),
    );
  }
  if (dot != null) {
    canvas.drawCircle(
      Offset(dot.x, dot.y),
      style.width / 2,
      paint..style = PaintingStyle.fill,
    );
  } else {
    canvas.drawPath(path, paint);
  }
  if (tail != null) canvas.drawPath(tail, paint..style = PaintingStyle.stroke);
  if (layered) canvas.restore();
}
