import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/artwork_painter.dart';
import 'package:whiteboard/src/editor/drawing_geometry.dart';
import 'package:whiteboard/src/editor/editor_scene.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

ArrowElementContent arrow({
  ArrowHeadStyle heads = ArrowHeadStyle.end,
  Point2? end,
  double width = 2,
}) => ArrowElementContent(
  start: Point2(20, 20),
  end: end ?? Point2(120, 20),
  style: StrokeStyle(color: 0xff123456, width: width),
  headLength: 20,
  headWidth: 16,
  heads: heads,
);

BoardDocument document(ElementContent content) => BoardDocument(
  id: 'drawing',
  revision: 0,
  assets: [],
  fontReferences: [],
  elements: [DocumentElement(id: ElementId('e'), content: content)],
);

void main() {
  test('extreme world dash tessellation remains bounded', () {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(100000000, 0);
    final dashed = dashedArtworkPath(path, .000001);
    expect(dashed.computeMetrics().length, lessThanOrEqualTo(4097));
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy defaults retain encoding; optional styles round-trip strictly',
    () {
      final legacy = DocumentCodec.encode(document(arrow()));
      expect(legacy, isNot(contains('heads')));
      expect(legacy, isNot(contains('dashed')));
      final decoded =
          DocumentCodec.decode(legacy).elements.single.content
              as ArrowElementContent;
      expect(decoded.heads, ArrowHeadStyle.end);
      expect(decoded.style.dashed, isFalse);
      final custom = ArrowElementContent(
        start: Point2(0, 0),
        end: Point2(50, 30),
        style: StrokeStyle(color: 0xff123456, width: 3, dashed: true),
        headLength: 15,
        headWidth: 10,
        heads: ArrowHeadStyle.both,
      );
      final encoded = DocumentCodec.encode(document(custom));
      final roundtrip =
          DocumentCodec.decode(encoded).elements.single.content
              as ArrowElementContent;
      expect(roundtrip.heads, ArrowHeadStyle.both);
      expect(roundtrip.style.dashed, isTrue);
      for (final bad in [null, 1, 'true']) {
        final map = jsonDecode(encoded) as Map<String, dynamic>;
        map['elements'][0]['content']['style']['dashed'] = bad;
        expect(
          () => DocumentCodec.decode(jsonEncode(map)),
          throwsFormatException,
        );
      }
      for (final bad in [null, 1, 'unknown']) {
        final map = jsonDecode(encoded) as Map<String, dynamic>;
        map['elements'][0]['content']['heads'] = bad;
        expect(
          () => DocumentCodec.decode(jsonEncode(map)),
          throwsFormatException,
        );
      }
    },
  );
  test('highlighter opacity legacy and explicit values validate', () {
    StrokeElementContent stroke(
      double? opacity, {
      StrokeKind kind = StrokeKind.highlighter,
    }) => StrokeElementContent(
      points: [Point2(0, 0)],
      style: StrokeStyle(color: 0xff000000, width: 8),
      kind: kind,
      highlighterOpacity: opacity,
    );
    final legacy = DocumentCodec.encode(document(stroke(null)));
    expect(legacy, isNot(contains('highlighterOpacity')));
    for (final value in [0.0, .35, 1.0]) {
      final encoded = DocumentCodec.encode(document(stroke(value)));
      final result =
          DocumentCodec.decode(encoded).elements.single.content
              as StrokeElementContent;
      expect(result.highlighterOpacity, value);
    }
    for (final value in [-.1, 1.1, double.nan, double.infinity]) {
      expect(() => stroke(value), throwsArgumentError);
    }
    expect(() => stroke(.5, kind: StrokeKind.pen), throwsArgumentError);
  });
  test(
    'arrow segments and stroke bounds agree in every direction and head mode',
    () {
      for (final end in [
        Point2(120, 20),
        Point2(-80, 20),
        Point2(20, 120),
        Point2(20, -80),
        Point2(100, 100),
      ]) {
        for (final mode in ArrowHeadStyle.values) {
          final content = arrow(heads: mode, end: end, width: 6);
          final segments = arrowSegments(content);
          expect(
            segments.length,
            mode == ArrowHeadStyle.none
                ? 1
                : mode == ArrowHeadStyle.both
                ? 5
                : 3,
          );
          final bounds = arrowBounds(content);
          for (final segment in segments) {
            expect(bounds.contains(segment.start), isTrue);
            expect(bounds.contains(segment.end), isTrue);
            expect(arrowHits(content, segment.start, 0), isTrue);
          }
          final scene = EditorScene(document(content));
          expect(scene.boundsOf(ElementId('e')), bounds);
        }
      }
      final short = arrow(end: Point2(22, 20), heads: ArrowHeadStyle.both);
      for (final segment in arrowSegments(short)) {
        expect(segment.start.x, inInclusiveRange(20, 22));
        expect(segment.end.x, inInclusiveRange(20, 22));
      }
      final scene = EditorScene(document(arrow()));
      expect(scene.hitTest(Point2(30, 27), worldTolerance: 0), isNull);
      expect(scene.hitTest(Point2(110, 24), worldTolerance: 0), ElementId('e'));
    },
  );
  test('dash extraction has deterministic width multiples', () {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(100, 0);
    final metrics = dashedArtworkPath(path, 2).computeMetrics().toList();
    expect(metrics.length, 9);
    expect(metrics.first.length, closeTo(8, .001));
    expect(metrics[1].getTangentForOffset(0)!.position.dx, closeTo(12, .001));
  });
  test('highlighter self-overlap and preview tail apply alpha once', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final path = ui.Path()
      ..moveTo(10, 20)
      ..lineTo(80, 20)
      ..lineTo(10, 20)
      ..lineTo(80, 20);
    final tail = ui.Path()
      ..moveTo(10, 20)
      ..lineTo(80, 20);
    paintFreehandPath(
      canvas,
      path,
      style: StrokeStyle(color: 0x8000ff00, width: 10),
      opacity: .5,
      highlighter: true,
      tail: tail,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 40);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(bytes.getUint8((20 * 100 + 40) * 4 + 3), inInclusiveRange(63, 65));
    image.dispose();
    picture.dispose();
  });
}
