import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../document/element.dart';
import '../geometry/geometry.dart';

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
    case ArrowElementContent(
      :final start,
      :final end,
      :final headLength,
      :final headWidth,
    ):
      final angle = math.atan2(end.y - start.y, end.x - start.x);
      final dx = math.cos(angle), dy = math.sin(angle);
      path
        ..moveTo(start.x, start.y)
        ..lineTo(end.x, end.y)
        ..moveTo(
          end.x - dx * headLength - dy * headWidth / 2,
          end.y - dy * headLength + dx * headWidth / 2,
        )
        ..lineTo(end.x, end.y)
        ..lineTo(
          end.x - dx * headLength + dy * headWidth / 2,
          end.y - dy * headLength - dx * headWidth / 2,
        );
    default:
      break;
  }
  return path;
}

/// Paints one element in its local space. The caller owns all supplied resources
/// and applies transforms, ancestor clipping and inherited opacity.
void paintElementArtwork(
  Canvas canvas,
  DocumentElement element, {
  Path? path,
  TextPainter? textLayout,
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
  final color = Color(style.color);
  final highlighter =
      content is StrokeElementContent && content.kind == StrokeKind.highlighter;
  final paint = Paint()
    ..color = color.withValues(alpha: color.a * alpha * (highlighter ? .28 : 1))
    ..style = PaintingStyle.stroke
    ..strokeWidth = style.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  if (content is StrokeElementContent && content.points.length == 1) {
    final point = content.points.single;
    canvas.drawCircle(
      Offset(point.x, point.y),
      style.width / 2,
      paint..style = PaintingStyle.fill,
    );
  } else {
    canvas.drawPath(shapePath, paint);
  }
}
