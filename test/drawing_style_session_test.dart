import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

ElementId _id(String value) => ElementId(value);
StrokeStyle _style({bool dashed = false}) =>
    StrokeStyle(color: 0xff102030, width: 3, dashed: dashed);
DocumentElement _element(
  String id,
  ElementContent content, {
  String? parent,
  bool locked = false,
  Transform2 transform = Transform2.identity,
}) => DocumentElement(
  id: _id(id),
  content: content,
  parentId: parent == null ? null : _id(parent),
  locked: locked,
  transform: transform,
);
ShapeElementContent _shape({bool outlined = true}) => ShapeElementContent(
  kind: ShapeKind.triangle,
  bounds: Bounds2(3, 5, 30, 40),
  fillColor: 0xff667788,
  stroke: outlined ? _style() : null,
);
BoardSession _session(List<DocumentElement> elements) => BoardSession(
  document: BoardDocument(
    id: 'drawing-style',
    revision: 0,
    elements: elements,
    assets: [],
    fontReferences: [],
  ),
);
ArrowElementContent _arrow() => ArrowElementContent(
  start: Point2(1, 2),
  end: Point2(30, 50),
  style: _style(),
  headLength: 7,
  headWidth: 4,
  heads: ArrowHeadStyle.start,
);

void main() {
  test(
    'styling a hierarchy commits once and preserves geometry IDs order and ownership',
    () {
      final s = _session([
        _element(
          'owner',
          const GroupElementContent(),
          transform: Transform2.rotation(.4),
        ),
        _element(
          'shape',
          _shape(),
          parent: 'owner',
          transform: Transform2.translation(10, 20),
        ),
        _element(
          'line',
          LineElementContent(
            start: Point2(2, 3),
            end: Point2(50, 60),
            style: _style(),
          ),
          parent: 'owner',
        ),
        _element('arrow', _arrow()),
        _element(
          'stroke',
          StrokeElementContent(
            points: [Point2(1, 2), Point2(20, 30)],
            style: _style(),
            kind: StrokeKind.highlighter,
            highlighterOpacity: .42,
          ),
        ),
      ]);
      final before = s.document;
      expect(
        s.styleMany(
          [_id('owner'), _id('shape'), _id('arrow'), _id('stroke')],
          strokeColor: 0xffabcdef,
          strokeWidth: 9,
          fillColor: 0xff00ff00,
          dashed: true,
          arrowHeads: ArrowHeadStyle.both,
        ),
        isTrue,
      );
      final styled = s.document;
      expect(styled.revision, 1);
      for (var i = 0; i < before.elements.length; i++) {
        final old = before.elements[i], updated = styled.elements[i];
        expect(updated.id, old.id);
        expect(updated.parentId, old.parentId);
        expect(updated.transform, old.transform);
        expect(updated.locked, old.locked);
        expect(updated.opacity, old.opacity);
      }
      final shape = styled.byId[_id('shape')]!.content as ShapeElementContent;
      expect(
        shape.bounds,
        (before.byId[_id('shape')]!.content as ShapeElementContent).bounds,
      );
      expect(shape.kind, ShapeKind.triangle);
      expect(shape.fillColor, 0xff00ff00);
      expect(
        (shape.stroke!.color, shape.stroke!.width, shape.stroke!.dashed),
        (0xffabcdef, 9, true),
      );
      final line = styled.byId[_id('line')]!.content as LineElementContent;
      expect((line.start, line.end), (Point2(2, 3), Point2(50, 60)));
      final arrow = styled.byId[_id('arrow')]!.content as ArrowElementContent;
      expect(
        (
          arrow.start,
          arrow.end,
          arrow.headLength,
          arrow.headWidth,
          arrow.heads,
        ),
        (Point2(1, 2), Point2(30, 50), 7, 4, ArrowHeadStyle.both),
      );
      final stroke =
          styled.byId[_id('stroke')]!.content as StrokeElementContent;
      expect(stroke.points, [Point2(1, 2), Point2(20, 30)]);
      expect(stroke.kind, StrokeKind.highlighter);
      expect(stroke.highlighterOpacity, .42);
      expect(s.undo(), isTrue);
      expect(s.document.revision, 2);
      for (var i = 0; i < before.elements.length; i++) {
        expect(
          s.document.elements[i].content,
          same(before.elements[i].content),
        );
      }
      expect(s.canUndo, isFalse);
      expect(s.redo(), isTrue);
      expect(s.document.revision, 3);
      for (var i = 0; i < styled.elements.length; i++) {
        expect(
          s.document.elements[i].content,
          same(styled.elements[i].content),
        );
      }
      final reopened = DocumentCodec.decode(DocumentCodec.encode(s.document));
      final reopenedArrow =
          reopened.byId[_id('arrow')]!.content as ArrowElementContent;
      expect(reopenedArrow.heads, ArrowHeadStyle.both);
      expect(reopenedArrow.style.dashed, isTrue);
      final reopenedStroke =
          reopened.byId[_id('stroke')]!.content as StrokeElementContent;
      expect(reopenedStroke.highlighterOpacity, .42);
      expect(reopenedStroke.points, stroke.points);
      expect(
        reopened.elements.map((e) => e.id),
        before.elements.map((e) => e.id),
      );
      expect(reopened.byId[_id('shape')]!.parentId, _id('owner'));
    },
  );

  test(
    'omitted style fields survive arrow changes duplication and reopening',
    () {
      final s = _session([_element('arrow', _arrow())]);
      expect(s.styleMany([_id('arrow')], dashed: true), isTrue);
      final arrow =
          s.document.byId[_id('arrow')]!.content as ArrowElementContent;
      expect(arrow.heads, ArrowHeadStyle.start);
      expect((arrow.style.color, arrow.style.width), (0xff102030, 3));
      final duplicate = s.duplicateMany([_id('arrow')]).single;
      final reopened = DocumentCodec.decode(DocumentCodec.encode(s.document));
      final copy = reopened.byId[duplicate]!.content as ArrowElementContent;
      expect(copy.heads, ArrowHeadStyle.start);
      expect(copy.style.dashed, isTrue);
      expect((copy.headLength, copy.headWidth), (7, 4));
      for (final heads in ArrowHeadStyle.values) {
        s.styleMany([_id('arrow')], arrowHeads: heads);
        expect(
          (s.document.byId[_id('arrow')]!.content as ArrowElementContent).heads,
          heads,
        );
      }
    },
  );

  test(
    'locked descendants inherited locks and unknown IDs reject the whole operation',
    () {
      final s = _session([
        _element('free', _shape()),
        _element('owner', const GroupElementContent()),
        _element('locked', _shape(), parent: 'owner', locked: true),
        _element('locked-owner', const GroupElementContent(), locked: true),
        _element('inherited', _shape(), parent: 'locked-owner'),
      ]);
      final before = s.document;
      for (final blocked in ['owner', 'locked', 'inherited', 'missing']) {
        expect(
          s.styleMany([_id('free'), _id(blocked)], strokeWidth: 7),
          isFalse,
        );
        expect(s.document, same(before));
        expect(s.canUndo, isFalse);
      }
    },
  );

  test(
    'no-op and ineligible properties do not consume revision or redo history',
    () {
      final s = _session([
        _element('shape', _shape()),
        _element(
          'line',
          LineElementContent(
            start: Point2.zero,
            end: Point2(20, 30),
            style: _style(),
          ),
        ),
      ]);
      s.styleMany([_id('shape')], strokeWidth: 8);
      s.undo();
      final before = s.document;
      expect(s.styleMany([_id('shape')]), isFalse);
      expect(
        s.styleMany(
          [_id('shape')],
          strokeColor: 0xff102030,
          strokeWidth: 3,
          fillColor: 0xff667788,
          dashed: false,
          arrowHeads: ArrowHeadStyle.both,
        ),
        isFalse,
      );
      expect(
        s.styleMany(
          [_id('line')],
          fillColor: 0xffff0000,
          arrowHeads: ArrowHeadStyle.both,
        ),
        isFalse,
      );
      expect(s.styleMany([], strokeWidth: 2), isFalse);
      expect(s.document, same(before));
      expect(s.canRedo, isTrue);
    },
  );

  test('fill clearing remains visible and invalid batches are atomic', () {
    final s = _session([
      _element('outlined', _shape()),
      _element('filled', _shape(outlined: false)),
    ]);
    final before = s.document;
    expect(
      () => s.styleMany([_id('outlined'), _id('filled')], clearFill: true),
      throwsArgumentError,
    );
    expect(s.document, same(before));
    expect(s.canUndo, isFalse);
    expect(s.styleMany([_id('outlined')], clearFill: true), isTrue);
    expect(
      (s.document.byId[_id('outlined')]!.content as ShapeElementContent)
          .fillColor,
      isNull,
    );
    expect(
      s.styleMany(
        [_id('filled')],
        strokeWidth: 4,
        strokeColor: 0xff445566,
        dashed: true,
        clearFill: true,
      ),
      isTrue,
    );
    final updated =
        s.document.byId[_id('filled')]!.content as ShapeElementContent;
    expect(updated.fillColor, isNull);
    expect(
      (updated.stroke!.color, updated.stroke!.width, updated.stroke!.dashed),
      (0xff445566, 4, true),
    );
    s.undo();
    expect(
      s.document.byId[_id('filled')]!.content,
      same(before.byId[_id('filled')]!.content),
    );
  });

  test(
    'highlighter opacity edits preserve pen and support legacy null values',
    () {
      final s = _session([
        _element(
          'highlighter',
          StrokeElementContent(
            points: [Point2.zero, Point2(20, 20)],
            style: _style(dashed: true),
            kind: StrokeKind.highlighter,
          ),
        ),
        _element(
          'pen',
          StrokeElementContent(
            points: [Point2.zero, Point2(20, 20)],
            style: _style(),
          ),
        ),
      ]);
      final before = s.document;
      expect(
        s.styleMany([_id('highlighter'), _id('pen')], highlighterOpacity: .65),
        isTrue,
      );
      expect(
        (s.document.byId[_id('highlighter')]!.content as StrokeElementContent)
            .highlighterOpacity,
        .65,
      );
      expect(
        s.document.byId[_id('pen')]!.content,
        same(before.byId[_id('pen')]!.content),
      );
      expect(
        s.styleMany([_id('highlighter')], highlighterOpacity: .65),
        isFalse,
      );
      s.styleMany([_id('highlighter')], strokeWidth: 6);
      expect(
        (s.document.byId[_id('highlighter')]!.content as StrokeElementContent)
            .highlighterOpacity,
        .65,
      );
      s.undo();
      s.undo();
      expect(
        (s.document.byId[_id('highlighter')]!.content as StrokeElementContent)
            .highlighterOpacity,
        isNull,
      );
    },
  );

  test('invalid parameters preserve document and redo branch', () {
    final s = _session([_element('shape', _shape())]);
    s.styleMany([_id('shape')], strokeWidth: 8);
    s.undo();
    final before = s.document;
    for (final action in <void Function()>[
      () => s.styleMany([_id('shape')], strokeWidth: 0),
      () => s.styleMany([_id('shape')], strokeWidth: double.nan),
      () => s.styleMany([_id('shape')], strokeColor: -1),
      () => s.styleMany([_id('shape')], fillColor: 0x100000000),
      () => s.styleMany([_id('shape')], fillColor: 0xff000000, clearFill: true),
      () => s.styleMany([_id('shape')], highlighterOpacity: double.infinity),
      () => s.styleMany([_id('shape')], highlighterOpacity: -0.1),
      () => s.styleMany([_id('shape')], highlighterOpacity: 1.1),
    ]) {
      expect(action, throwsArgumentError);
      expect(s.document, same(before));
      expect(s.canRedo, isTrue);
    }
  });
}
