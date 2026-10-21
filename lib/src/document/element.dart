import '../geometry/geometry.dart';

/// Maximum safe integer revision across native and JavaScript targets.
const maximumDocumentRevision = 9007199254740991;

/// Opaque caller-provided identity; editing an element never changes its ID.
final class ElementId {
  factory ElementId(String value) {
    _requireIdentifier(value, 'value');
    return ElementId._(value);
  }

  const ElementId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is ElementId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

enum ShapeKind { rectangle, ellipse, triangle }

enum StrokeKind { pen, highlighter }

enum ElementTextDirection { auto, ltr, rtl }

enum ElementTextAlignment { start, center, end, left, right }

/// Authoring intent; measured text layout and IME state are owned elsewhere.
enum TextSizing { auto, autoHeight, fixed }

final class StrokeStyle {
  StrokeStyle({required this.color, required this.width, this.dashed = false}) {
    _requireColor(color, 'color');
    _requirePositive(width, 'width');
  }

  final int color;
  final double width;
  final bool dashed;
}

final class ElementTextStyle {
  ElementTextStyle({
    required this.fontId,
    required this.fontSize,
    required this.color,
  }) {
    _requireIdentifier(fontId, 'fontId');
    _requirePositive(fontSize, 'fontSize');
    _requireColor(color, 'color');
  }

  final String fontId;
  final double fontSize;
  final int color;
}

sealed class ElementContent {
  const ElementContent();

  bool get canOwnChildren => false;
}

final class ShapeElementContent extends ElementContent {
  ShapeElementContent({
    required this.kind,
    required this.bounds,
    this.fillColor,
    this.stroke,
  }) {
    _requireArea(bounds);
    if (fillColor != null) _requireColor(fillColor!, 'fillColor');
    if (fillColor == null && stroke == null) {
      throw ArgumentError('A shape needs a fill or stroke.');
    }
  }

  final ShapeKind kind;
  final Bounds2 bounds;
  final int? fillColor;
  final StrokeStyle? stroke;
}

final class StrokeElementContent extends ElementContent {
  StrokeElementContent({
    required Iterable<Point2> points,
    required this.style,
    this.kind = StrokeKind.pen,
    this.highlighterOpacity,
  }) : points = List.unmodifiable(points) {
    if (this.points.isEmpty) throw ArgumentError('A stroke needs points.');
    if (highlighterOpacity != null &&
        (kind != StrokeKind.highlighter ||
            !highlighterOpacity!.isFinite ||
            highlighterOpacity! < 0 ||
            highlighterOpacity! > 1)) {
      throw ArgumentError.value(highlighterOpacity, 'highlighterOpacity');
    }
    // Validate the local extent, including overflow between finite points.
    Bounds2.fromPoints(this.points);
  }

  final List<Point2> points;
  final StrokeStyle style;
  final StrokeKind kind;
  final double? highlighterOpacity;
}

final class LineElementContent extends ElementContent {
  LineElementContent({
    required this.start,
    required this.end,
    required this.style,
  }) {
    _requireEndpoints(start, end);
  }

  final Point2 start;
  final Point2 end;
  final StrokeStyle style;
}

enum ArrowHeadStyle { none, start, end, both }

final class ArrowElementContent extends ElementContent {
  ArrowElementContent({
    required this.start,
    required this.end,
    required this.style,
    required this.headLength,
    required this.headWidth,
    this.heads = ArrowHeadStyle.end,
  }) {
    _requireEndpoints(start, end);
    _requirePositive(headLength, 'headLength');
    _requirePositive(headWidth, 'headWidth');
  }

  final Point2 start;
  final Point2 end;
  final StrokeStyle style;
  final double headLength;
  final double headWidth;
  final ArrowHeadStyle heads;
}

final class TextElementContent extends ElementContent {
  TextElementContent({
    required this.text,
    required this.bounds,
    required this.style,
    this.direction = ElementTextDirection.auto,
    this.alignment = ElementTextAlignment.start,
    this.sizing = TextSizing.auto,
  }) {
    _requireArea(bounds);
  }

  final String text;
  final Bounds2 bounds;
  final ElementTextStyle style;
  final ElementTextDirection direction;
  final ElementTextAlignment alignment;
  final TextSizing sizing;
}

final class StickyNoteElementContent extends ElementContent {
  StickyNoteElementContent({
    required this.text,
    required this.bounds,
    required this.style,
    required this.backgroundColor,
    this.direction = ElementTextDirection.auto,
    this.alignment = ElementTextAlignment.start,
    this.sizing = TextSizing.autoHeight,
  }) {
    _requireArea(bounds);
    _requireColor(backgroundColor, 'backgroundColor');
  }

  final String text;
  final Bounds2 bounds;
  final ElementTextStyle style;
  final int backgroundColor;
  final ElementTextDirection direction;
  final ElementTextAlignment alignment;
  final TextSizing sizing;
}

final class ImageElementContent extends ElementContent {
  ImageElementContent({required this.assetId, required this.bounds}) {
    _requireIdentifier(assetId, 'assetId');
    _requireArea(bounds);
  }

  final String assetId;
  final Bounds2 bounds;
}

final class GroupElementContent extends ElementContent {
  const GroupElementContent();

  @override
  bool get canOwnChildren => true;
}

/// Defines an export area independently of element ownership.
final class ExportFrameElementContent extends ElementContent {
  ExportFrameElementContent({
    required this.bounds,
    this.label = '',
    this.outputWidth,
    this.outputHeight,
  }) {
    _requireArea(bounds);
    if ((outputWidth == null) != (outputHeight == null) ||
        (outputWidth != null && (outputWidth! < 1 || outputWidth! > 16384)) ||
        (outputHeight != null &&
            (outputHeight! < 1 || outputHeight! > 16384))) {
      throw ArgumentError(
        'Export dimensions must be paired integers from 1 to 16384.',
      );
    }
  }

  final Bounds2 bounds;
  final String label;
  final int? outputWidth;
  final int? outputHeight;
}

/// Children retain membership outside these bounds; export applies clipping.
final class ContainerFrameElementContent extends ElementContent {
  ContainerFrameElementContent({required this.bounds, this.label = ''}) {
    _requireArea(bounds);
  }

  final Bounds2 bounds;
  final String label;

  @override
  bool get canOwnChildren => true;
}

final class DocumentElement {
  DocumentElement({
    required this.id,
    required this.content,
    this.parentId,
    this.transform = Transform2.identity,
    this.locked = false,
    this.revision = 0,
    this.opacity = 1,
  }) {
    if (revision < 0 || revision > maximumDocumentRevision) {
      throw ArgumentError.value(revision, 'revision');
    }
    if (!opacity.isFinite || opacity < 0 || opacity > 1) {
      throw ArgumentError.value(opacity, 'opacity');
    }
  }

  final ElementId id;
  final ElementId? parentId;
  final Transform2 transform;
  final bool locked;
  final int revision;
  final double opacity;
  final ElementContent content;

  /// Ownership changes must go through a validated document operation.
  DocumentElement copyWith({
    Transform2? transform,
    bool? locked,
    int? revision,
    double? opacity,
    ElementContent? content,
  }) => DocumentElement(
    id: id,
    parentId: parentId,
    transform: transform ?? this.transform,
    locked: locked ?? this.locked,
    revision: revision ?? this.revision,
    opacity: opacity ?? this.opacity,
    content: content ?? this.content,
  );
}

void _requireIdentifier(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name);
}

void _requirePositive(double value, String name) {
  if (!value.isFinite || value <= 0) throw ArgumentError.value(value, name);
}

void _requireColor(int value, String name) {
  if (value < 0 || value > 0xffffffff) throw ArgumentError.value(value, name);
}

void _requireArea(Bounds2 bounds) {
  if (bounds.width <= 0 || bounds.height <= 0) {
    throw ArgumentError('Authoring rectangles must have positive dimensions.');
  }
}

void _requireEndpoints(Point2 start, Point2 end) {
  if (start == end) throw ArgumentError('Endpoints must differ.');
  Bounds2.fromPoints([start, end]);
}
