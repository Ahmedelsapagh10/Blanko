import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/document_geometry.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

final _bounds = Bounds2(0, 0, 200, 100);
ElementId _id(String value) => ElementId(value);
DocumentElement _frame(
  String value, {
  String? parent,
  bool locked = false,
  Transform2 transform = Transform2.identity,
}) => DocumentElement(
  id: _id(value),
  parentId: parent == null ? null : _id(parent),
  transform: transform,
  locked: locked,
  content: ContainerFrameElementContent(bounds: _bounds, label: value),
);
DocumentElement _shape(
  String value, {
  String? parent,
  Transform2 transform = Transform2.identity,
}) => DocumentElement(
  id: _id(value),
  parentId: parent == null ? null : _id(parent),
  transform: transform,
  content: ShapeElementContent(
    kind: ShapeKind.rectangle,
    bounds: Bounds2(0, 0, 20, 10),
    fillColor: 0xff123456,
  ),
);
BoardSession _session(List<DocumentElement> elements) => BoardSession(
  document: BoardDocument(
    id: 'frames',
    revision: 0,
    elements: elements,
    assets: const [],
    fontReferences: const [],
  ),
);
void _nearTransform(Transform2 actual, Transform2 expected) {
  for (final point in [Point2.zero, Point2(1, 0), Point2(0, 1)]) {
    expect(actual.apply(point).x, closeTo(expected.apply(point).x, 1e-9));
    expect(actual.apply(point).y, closeTo(expected.apply(point).y, 1e-9));
  }
}

void main() {
  test(
    'reparent preserves transformed world geometry, source order and undo',
    () {
      final session = _session([
        _frame(
          'a',
          transform: Transform2.translation(50, -30) * Transform2.rotation(.4),
        ),
        _frame(
          'b',
          transform: Transform2.translation(-80, 20) * Transform2.scale(2, 2),
        ),
        _shape('leaf', parent: 'a', transform: Transform2.translation(12, 17)),
        _shape('sibling', parent: 'b'),
      ]);
      final sourceIds = session.document.elements.map((e) => e.id).toList();
      final world = DocumentGeometry(
        session.document,
      ).worldTransformOf(_id('leaf'));
      expect(session.reparent(_id('leaf'), _id('b')), isTrue);
      expect(session.document.elements.map((e) => e.id), sourceIds);
      _nearTransform(
        DocumentGeometry(session.document).worldTransformOf(_id('leaf')),
        world,
      );
      expect(session.document.childrenOf(_id('b')).map((e) => e.id), [
        _id('leaf'),
        _id('sibling'),
      ]);
      expect(session.undo(), isTrue);
      expect(session.document.byId[_id('leaf')]!.parentId, _id('a'));
      expect(session.redo(), isTrue);
      expect(session.reparent(_id('leaf'), null), isTrue);
      _nearTransform(
        DocumentGeometry(session.document).worldTransformOf(_id('leaf')),
        world,
      );
      expect(session.document.byId[_id('leaf')]!.parentId, isNull);
    },
  );

  test(
    'cycles, nonowners, locked owners and locked subtrees cannot reparent',
    () {
      final session = _session([
        _frame('a'),
        _frame('b', parent: 'a'),
        _shape('leaf', parent: 'b'),
        _frame('locked', locked: true),
        _frame('with-locked'),
        _frame('locked-child', parent: 'with-locked', locked: true),
      ]);
      final before = session.document;
      expect(session.reparent(_id('a'), _id('b')), isFalse);
      expect(session.reparent(_id('b'), _id('b')), isFalse);
      expect(session.reparent(_id('b'), _id('leaf')), isFalse);
      expect(session.reparent(_id('b'), _id('locked')), isFalse);
      expect(session.reparent(_id('with-locked'), _id('a')), isFalse);
      expect(session.reparent(_id('leaf'), _id('missing')), isFalse);
      expect(session.document, same(before));
      expect(session.canUndo, isFalse);
    },
  );

  test(
    'container movement inherits world translation once and resize leaves children',
    () {
      final session = _session([
        _frame('a', transform: Transform2.translation(20, 30)),
        _frame('b', parent: 'a', transform: Transform2.rotation(.3)),
        _shape('leaf', parent: 'b', transform: Transform2.translation(10, 15)),
      ]);
      final before = DocumentGeometry(
        session.document,
      ).worldTransformOf(_id('leaf'));
      expect(session.translate(_id('a'), Point2(45, -15)), isTrue);
      final moved = DocumentGeometry(
        session.document,
      ).worldTransformOf(_id('leaf'));
      _nearTransform(moved, Transform2.translation(45, -15) * before);
      expect(session.resize(_id('a'), Bounds2(-10, -20, 250, 160)), isTrue);
      _nearTransform(
        DocumentGeometry(session.document).worldTransformOf(_id('leaf')),
        moved,
      );
      expect(session.undo(), isTrue);
      expect(
        (session.document.byId[_id('a')]!.content
                as ContainerFrameElementContent)
            .bounds,
        _bounds,
      );
      expect(session.undo(), isTrue);
      _nearTransform(
        DocumentGeometry(session.document).worldTransformOf(_id('leaf')),
        before,
      );
    },
  );

  test(
    'duplicate copies nested descendants, order, locks and world offset',
    () {
      final session = _session([
        _frame(
          'owner',
          transform: Transform2.rotation(.7) * Transform2.scale(2, 2),
        ),
        _frame(
          'frame',
          parent: 'owner',
          transform: Transform2.translation(10, 20),
        ),
        _frame('nested', parent: 'frame'),
        _shape(
          'leaf',
          parent: 'nested',
          transform: Transform2.translation(8, 9),
        ),
        _shape('last', parent: 'frame'),
      ]);
      final original = session.document;
      final before = DocumentGeometry(original);
      final duplicate = session.duplicate(_id('frame'), Point2(24, 24))!;
      final copiedNested = session.document.childrenOf(duplicate).first;
      final copiedLast = session.document.childrenOf(duplicate).last;
      final copiedLeaf = session.document.childrenOf(copiedNested.id).single;
      expect(copiedLast.content, same(original.byId[_id('last')]!.content));
      expect(copiedLeaf.content, same(original.byId[_id('leaf')]!.content));
      expect(session.document.elements.length, original.elements.length + 4);
      final after = DocumentGeometry(session.document);
      _nearTransform(
        after.worldTransformOf(copiedLeaf.id),
        Transform2.translation(24, 24) * before.worldTransformOf(_id('leaf')),
      );
      expect(session.undo(), isTrue);
      expect(
        session.document.elements.map((e) => e.id),
        original.elements.map((e) => e.id),
      );
      expect(session.redo(), isTrue);
      expect(session.document.byId.containsKey(copiedLeaf.id), isTrue);
    },
  );

  test('export label/dimensions survive resize, undo and codec reopening', () {
    final session = _session([]);
    final id = session.insert(ExportFrameElementContent(bounds: _bounds));
    final editedBounds = Bounds2(-5, -5, 195, 95);
    expect(
      session.updateFrame(
        id,
        label: 'Arabic لوحة',
        bounds: editedBounds,
        outputWidth: 3840,
        outputHeight: 2160,
      ),
      isTrue,
    );
    expect(
      session.updateFrame(
        id,
        label: 'Arabic لوحة',
        bounds: editedBounds,
        outputWidth: 3840,
        outputHeight: 2160,
      ),
      isFalse,
    );
    expect(session.resize(id, Bounds2(-10, -10, 100, 90)), isTrue);
    var content =
        session.document.byId[id]!.content as ExportFrameElementContent;
    expect(content.outputWidth, 3840);
    expect(content.outputHeight, 2160);
    final encoded = DocumentCodec.encode(session.document);
    final reopened = DocumentCodec.decode(encoded);
    content = reopened.byId[id]!.content as ExportFrameElementContent;
    expect(content.label, 'Arabic لوحة');
    expect(content.outputWidth, 3840);
    expect(content.bounds, Bounds2(-10, -10, 100, 90));
    expect(session.undo(), isTrue);
    expect(session.undo(), isTrue);
    content = session.document.byId[id]!.content as ExportFrameElementContent;
    expect(content.label, isEmpty);
    expect(content.outputWidth, isNull);
    expect(content.bounds, _bounds);
    expect(session.redo(), isTrue);
    content = session.document.byId[id]!.content as ExportFrameElementContent;
    expect(content.outputHeight, 2160);
  });

  test(
    'legacy frame schema reads, incomplete or oversized dimensions reject',
    () {
      final session = _session([]);
      final id = session.insert(
        ExportFrameElementContent(bounds: _bounds, label: 'legacy'),
      );
      final source = DocumentCodec.encode(session.document);
      expect(source, isNot(contains('outputWidth')));
      expect(
        (DocumentCodec.decode(source).byId[id]!.content
                as ExportFrameElementContent)
            .outputWidth,
        isNull,
      );
      final root = jsonDecode(source) as Map<String, dynamic>;
      final content = root['elements'][0]['content'] as Map<String, dynamic>;
      content['outputWidth'] = 300;
      expect(
        () => DocumentCodec.decode(jsonEncode(root)),
        throwsFormatException,
      );
      content['outputHeight'] = 0;
      expect(
        () => DocumentCodec.decode(jsonEncode(root)),
        throwsFormatException,
      );
      expect(
        () => ExportFrameElementContent(
          bounds: _bounds,
          outputWidth: 16385,
          outputHeight: 1,
        ),
        throwsArgumentError,
      );
    },
  );

  test('resize retains text and sticky direction, alignment and sizing', () {
    final session = BoardSession();
    final style = ElementTextStyle(
      fontId: 'font',
      fontSize: 24,
      color: 0xff000000,
    );
    final text = session.insert(
      TextElementContent(
        text: 'مرحبا',
        bounds: _bounds,
        style: style,
        direction: ElementTextDirection.rtl,
        alignment: ElementTextAlignment.end,
        sizing: TextSizing.fixed,
      ),
    );
    final sticky = session.insert(
      StickyNoteElementContent(
        text: 'مرحبا',
        bounds: _bounds,
        style: style,
        backgroundColor: 0xffffaa00,
        direction: ElementTextDirection.rtl,
        alignment: ElementTextAlignment.center,
        sizing: TextSizing.fixed,
      ),
    );
    final resized = Bounds2(0, 0, 300, 200);
    session.resize(text, resized);
    session.resize(sticky, resized);
    final t = session.document.byId[text]!.content as TextElementContent;
    final s =
        session.document.byId[sticky]!.content as StickyNoteElementContent;
    expect(t.direction, ElementTextDirection.rtl);
    expect(t.alignment, ElementTextAlignment.end);
    expect(t.sizing, TextSizing.fixed);
    expect(s.direction, ElementTextDirection.rtl);
    expect(s.alignment, ElementTextAlignment.center);
    expect(s.sizing, TextSizing.fixed);
  });
}
