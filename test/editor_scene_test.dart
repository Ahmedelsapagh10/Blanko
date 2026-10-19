import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_scene.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/viewport/camera.dart';

DocumentElement shape(
  String id, {
  ShapeKind kind = ShapeKind.rectangle,
  Transform2 transform = Transform2.identity,
  String? parent,
  bool locked = false,
  double opacity = 1,
  bool filled = true,
  double strokeWidth = 2,
}) => DocumentElement(
  id: ElementId(id),
  parentId: parent == null ? null : ElementId(parent),
  transform: transform,
  locked: locked,
  opacity: opacity,
  content: ShapeElementContent(
    kind: kind,
    bounds: Bounds2(0, 0, 100, 60),
    fillColor: filled ? 0xffeeeeee : null,
    stroke: StrokeStyle(color: 0xff000000, width: strokeWidth),
  ),
);

EditorScene scene(List<DocumentElement> elements) =>
    EditorScene(BoardDocument(id: 'board', revision: 0, elements: elements));

void main() {
  test(
    'topmost painted hit wins and culling preserves relative paint order',
    () {
      final resolved = scene([
        shape('a'),
        shape('b'),
        shape('far', transform: Transform2.translation(1000, 1000)),
      ]);
      expect(
        resolved.hitTest(Point2(30, 30), worldTolerance: 0),
        ElementId('b'),
      );
      expect(resolved.visible(Bounds2(0, 0, 90, 50)).map((e) => e.id), [
        ElementId('a'),
        ElementId('b'),
      ]);
      expect(() => resolved.paintOrder.clear(), throwsUnsupportedError);
    },
  );

  test('rectangle ellipse triangle outlines do not hit empty interiors', () {
    for (final kind in ShapeKind.values) {
      final resolved = scene([shape('shape', kind: kind, filled: false)]);
      expect(
        resolved.hitTest(Point2(50, 30), worldTolerance: 1),
        isNull,
        reason: '$kind outline center',
      );
      final edge = kind == ShapeKind.triangle ? Point2(50, 0) : Point2(100, 30);
      expect(resolved.hitTest(edge, worldTolerance: 0.1), ElementId('shape'));
    }
  });

  test(
    'ellipse and triangle filled hits reject empty bounding rectangle corners',
    () {
      for (final kind in [ShapeKind.ellipse, ShapeKind.triangle]) {
        final resolved = scene([shape('shape', kind: kind)]);
        expect(resolved.hitTest(Point2(1, 1), worldTolerance: 0), isNull);
        expect(
          resolved.hitTest(Point2(50, 30), worldTolerance: 0),
          ElementId('shape'),
        );
      }
    },
  );

  test('stroke hit follows segments, singleton dots, and repeated points', () {
    final pen = DocumentElement(
      id: ElementId('pen'),
      content: StrokeElementContent(
        points: [Point2(0, 0), Point2(0, 0), Point2(100, 100)],
        style: StrokeStyle(color: 0xff000000, width: 4),
      ),
    );
    final dot = DocumentElement(
      id: ElementId('dot'),
      content: StrokeElementContent(
        kind: StrokeKind.highlighter,
        points: [Point2(200, 200)],
        style: StrokeStyle(color: 0x88ffff00, width: 12),
      ),
    );
    final resolved = scene([pen, dot]);
    expect(resolved.hitTest(Point2(51, 50), worldTolerance: 0), pen.id);
    expect(resolved.hitTest(Point2(70, 20), worldTolerance: 0), isNull);
    expect(resolved.hitTest(Point2(205, 200), worldTolerance: 0), dot.id);
    expect(resolved.hitTest(Point2(207, 200), worldTolerance: 0), isNull);
    expect(resolved.boundsOf(dot.id), Bounds2(194, 194, 206, 206));
  });

  test('line uses round endpoint tolerance and includes stroke in culling', () {
    final line = DocumentElement(
      id: ElementId('line'),
      content: LineElementContent(
        start: Point2(0, 0),
        end: Point2(100, 0),
        style: StrokeStyle(color: 0xff000000, width: 10),
      ),
    );
    final resolved = scene([line]);
    expect(resolved.visible(Bounds2(20, -4, 30, -3)).single.id, line.id);
    expect(resolved.hitTest(Point2(-4, 0), worldTolerance: 0), line.id);
    expect(resolved.hitTest(Point2(50, 6), worldTolerance: 0), isNull);
    expect(resolved.hitTest(Point2(50, 6), worldTolerance: 2), line.id);
  });

  test('nested rotation scale and translation resolve world coordinates', () {
    final parent = DocumentElement(
      id: ElementId('group'),
      content: const GroupElementContent(),
      transform:
          Transform2.translation(400, -200) * Transform2.rotation(math.pi / 2),
    );
    final child = shape(
      'child',
      parent: 'group',
      transform: Transform2.scale(2, 2),
    );
    final resolved = scene([parent, child]);
    final world = resolved.worldTransformOf(child.id).apply(Point2(50, 30));
    expect(resolved.hitTest(world, worldTolerance: 0), child.id);
    expect(resolved.paintOrder.map((e) => e.id), [child.id]);
    expect(resolved.boundsOf(parent.id), resolved.boundsOf(child.id));
    expect(resolved.boundsOf(child.id).contains(world), isTrue);
  });

  test('locked and hidden ancestors suppress child interaction', () {
    final resolved = scene([
      shape('under'),
      DocumentElement(
        id: ElementId('locked'),
        content: const GroupElementContent(),
        locked: true,
      ),
      shape('locked-child', parent: 'locked'),
      DocumentElement(
        id: ElementId('hidden'),
        content: const GroupElementContent(),
        opacity: 0,
      ),
      shape('hidden-child', parent: 'hidden'),
      shape('hidden-top', opacity: 0),
    ]);
    expect(
      resolved.hitTest(Point2(50, 30), worldTolerance: 0),
      ElementId('under'),
    );
    expect(resolved.paintOrder.map((e) => e.id), [
      ElementId('under'),
      ElementId('locked-child'),
    ]);
  });

  test('screen hit tolerance remains constant through camera pan and zoom', () {
    final resolved = scene([shape('outline', filled: false)]);
    for (final zoom in [0.02, 0.5, 1.0, 8.0, 32.0]) {
      final camera = Camera(zoom: zoom, translation: Point2(500, -300));
      final edge = camera.worldToViewport(Point2(100, 30));
      final insideTolerance = camera.viewportToWorld(edge + Point2(3, 0));
      final outsideTolerance = camera.viewportToWorld(
        edge + Point2(5 + zoom, 0),
      );
      expect(
        resolved.hitTest(
          insideTolerance,
          worldTolerance: camera.worldTolerance(4),
        ),
        ElementId('outline'),
        reason: 'zoom $zoom',
      );
      expect(
        resolved.hitTest(
          outsideTolerance,
          worldTolerance: camera.worldTolerance(4),
        ),
        isNull,
        reason: 'zoom $zoom',
      );
    }
  });

  test(
    'large positive and negative worlds retain precision and query results',
    () {
      for (final origin in [-1e9, 1e9]) {
        final resolved = scene([
          shape('far', transform: Transform2.translation(origin, -origin)),
        ]);
        expect(
          resolved.hitTest(
            Point2(origin + 50, -origin + 30),
            worldTolerance: 0,
          ),
          ElementId('far'),
        );
        expect(
          resolved.visible(
            Bounds2(origin - 2, -origin - 2, origin + 102, -origin + 62),
          ),
          hasLength(1),
        );
        expect(resolved.visible(Bounds2(0, 0, 100, 100)), isEmpty);
      }
    },
  );

  test(
    'unsupported existing content and empty groups load without resource ownership',
    () {
      final empty = DocumentElement(
        id: ElementId('empty'),
        content: const GroupElementContent(),
      );
      final image = DocumentElement(
        id: ElementId('image'),
        content: ImageElementContent(
          assetId: 'external',
          bounds: Bounds2(200, 200, 300, 300),
        ),
      );
      final resolved = scene([empty, image]);
      expect(resolved.boundsOf(empty.id), Bounds2(0, 0, 0, 0));
      expect(resolved.hitTest(Point2(250, 250), worldTolerance: 0), image.id);
      expect(
        () => resolved.hitTest(Point2.zero, worldTolerance: -1),
        throwsArgumentError,
      );
      expect(
        () => resolved.boundsOf(ElementId('missing')),
        throwsArgumentError,
      );
    },
  );
}
