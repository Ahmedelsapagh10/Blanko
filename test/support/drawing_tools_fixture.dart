import 'dart:math' as math;
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/stroke_sampling.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'image_test_bytes.dart';

BoardDocument drawingToolsFixture() {
  final sampler = StrokeSampler(tolerance: .65);
  final points = <Point2>[];
  for (final p in [
    Point2(25, 260),
    Point2(60, 230),
    Point2(95, 245),
    Point2(130, 290),
    Point2(165, 275),
    Point2(210, 255),
  ]) {
    points.addAll(sampler.add(p));
  }
  points.addAll(sampler.finish(Point2(230, 275)));
  DocumentElement item(
    String id,
    ElementContent content, {
    Transform2 transform = Transform2.identity,
  }) => DocumentElement(
    id: ElementId(id),
    content: content,
    transform: transform,
  );
  final ink = StrokeStyle(color: 0xff2563eb, width: 4);
  return BoardDocument(
    id: 'drawing-tools-proof',
    title: 'Drawing tools proof',
    revision: 0,
    assets: [
      DocumentAssetReference(
        id: 'drawing-image',
        mimeType: 'image/png',
        pixelWidth: 64,
        pixelHeight: 32,
        byteLength: imageTestPng().length,
      ),
    ],
    fontReferences: [
      DocumentFontReference(id: 'editor-sans-v1', family: 'Roboto'),
    ],
    elements: [
      item(
        'frame',
        ExportFrameElementContent(
          bounds: Bounds2(0, 0, 600, 400),
          label: 'Tools proof',
        ),
      ),
      item(
        'title',
        TextElementContent(
          text: 'Drawing tools — أدوات الرسم',
          bounds: Bounds2(20, 15, 580, 70),
          style: ElementTextStyle(
            fontId: 'editor-sans-v1',
            fontSize: 25,
            color: 0xff172038,
          ),
        ),
      ),
      item(
        'rect',
        ShapeElementContent(
          kind: ShapeKind.rectangle,
          bounds: Bounds2(30, 100, 180, 180),
          fillColor: 0x802563eb,
          stroke: StrokeStyle(color: 0xff2563eb, width: 4, dashed: true),
        ),
      ),
      item(
        'circle',
        ShapeElementContent(
          kind: ShapeKind.ellipse,
          bounds: Bounds2(220, 100, 300, 180),
          fillColor: 0x8039ad70,
          stroke: StrokeStyle(color: 0xff15803d, width: 3),
        ),
      ),
      item(
        'image',
        ImageElementContent(
          assetId: 'drawing-image',
          bounds: Bounds2(345, 105, 473, 169),
        ),
      ),
      item(
        'note',
        StickyNoteElementContent(
          text: 'ملاحظة\nUniform PNG',
          bounds: Bounds2(340, 235, 565, 355),
          style: ElementTextStyle(
            fontId: 'editor-sans-v1',
            fontSize: 20,
            color: 0xff172038,
          ),
          backgroundColor: 0xffffe070,
        ),
      ),
      item('pen', StrokeElementContent(points: points, style: ink)),
      item(
        'arrow',
        ArrowElementContent(
          start: Point2(0, 0),
          end: Point2(110, 80),
          style: StrokeStyle(color: 0xff8822aa, width: 4),
          headLength: 18,
          headWidth: 16,
          heads: ArrowHeadStyle.both,
        ),
        transform:
            Transform2.translation(210, 215) *
            Transform2.rotation(-math.pi / 12),
      ),
      item(
        'marker-text',
        StrokeElementContent(
          points: [Point2(20, 42), Point2(560, 42)],
          style: StrokeStyle(color: 0xffffd54f, width: 26),
          kind: StrokeKind.highlighter,
          highlighterOpacity: .35,
        ),
      ),
      item(
        'marker-image',
        StrokeElementContent(
          points: [Point2(335, 135), Point2(500, 135)],
          style: StrokeStyle(color: 0xffffd54f, width: 20),
          kind: StrokeKind.highlighter,
          highlighterOpacity: .35,
        ),
      ),
    ],
  );
}
