import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

DocumentElement element(
  String id, {
  String? parent,
  ElementContent? content,
  Transform2 transform = Transform2.identity,
}) => DocumentElement(
  id: ElementId(id),
  parentId: parent == null ? null : ElementId(parent),
  transform: transform,
  content: content ?? const GroupElementContent(),
);

BoardDocument document(Iterable<DocumentElement> elements) =>
    BoardDocument(id: 'board', revision: 0, elements: elements);

void main() {
  final box = Bounds2(0, 0, 120, 80);
  final strokeStyle = StrokeStyle(color: 0x80336699, width: 2.5);
  final textStyle = ElementTextStyle(
    fontId: 'curated-font',
    fontSize: 18,
    color: 0xff112233,
  );

  test(
    'IDs are opaque values and replacements preserve identity and ownership',
    () {
      final id = ElementId(' caller:id / العربية ');
      expect(id.value, ' caller:id / العربية ');
      expect(id, ElementId(id.value));
      expect({id, ElementId(id.value)}, hasLength(1));
      expect(id, isNot(ElementId('caller:id / العربية')));
      final original = DocumentElement(
        id: id,
        parentId: ElementId('parent'),
        content: const GroupElementContent(),
      );
      final replacement = original.copyWith(
        transform: Transform2.translation(4, -8),
        locked: true,
        content: ContainerFrameElementContent(bounds: box),
      );
      expect(replacement.id, same(id));
      expect(replacement.parentId, same(original.parentId));
      expect(replacement.transform, Transform2.translation(4, -8));
      expect(replacement.locked, isTrue);
      expect(original.transform, Transform2.identity);
      expect(original.locked, isFalse);
      expect(original.content, isA<GroupElementContent>());
      final moved = original.copyWith(transform: Transform2.translation(1, 2));
      expect(moved.content, same(original.content));
      expect(() => ElementId(''), throwsArgumentError);
      expect(() => ElementId(' \n\t'), throwsArgumentError);
    },
  );

  test(
    'all required content types retain authoring data without UI resources',
    () {
      final contents = <ElementContent>[
        for (final kind in ShapeKind.values)
          ShapeElementContent(
            kind: kind,
            bounds: box,
            fillColor: 0xffeeeeee,
            stroke: strokeStyle,
          ),
        for (final kind in StrokeKind.values)
          StrokeElementContent(
            points: [Point2.zero, Point2(4, 8)],
            style: strokeStyle,
            kind: kind,
          ),
        LineElementContent(
          start: Point2.zero,
          end: Point2(40, 10),
          style: strokeStyle,
        ),
        ArrowElementContent(
          start: Point2.zero,
          end: Point2(80, 20),
          style: strokeStyle,
          headLength: 12,
          headWidth: 8,
        ),
        TextElementContent(
          text: 'Hello العربية\nSecond line',
          bounds: box,
          style: textStyle,
          direction: ElementTextDirection.rtl,
          alignment: ElementTextAlignment.right,
          sizing: TextSizing.autoHeight,
        ),
        StickyNoteElementContent(
          text: 'ملاحظة\nA note',
          bounds: box,
          style: textStyle,
          backgroundColor: 0xffffee88,
        ),
        ImageElementContent(assetId: 'original-image', bounds: box),
        const GroupElementContent(),
        ExportFrameElementContent(bounds: box, label: 'Export'),
        ContainerFrameElementContent(bounds: box, label: 'Container'),
      ];
      final board = document([
        for (var i = 0; i < contents.length; i++)
          element('e$i', content: contents[i]),
      ]);
      expect(board.elements, hasLength(13));
      for (var i = 0; i < contents.length; i++) {
        expect(board.elements[i].content, same(contents[i]));
      }
      final text = contents.whereType<TextElementContent>().single;
      expect(text.text, 'Hello العربية\nSecond line');
      expect(text.style, same(textStyle));
      expect(text.style.fontId, 'curated-font');
      expect(text.direction, ElementTextDirection.rtl);
      expect(text.alignment, ElementTextAlignment.right);
      expect(text.sizing, TextSizing.autoHeight);
      final note = contents.whereType<StickyNoteElementContent>().single;
      expect(note.backgroundColor, 0xffffee88);
      expect(note.direction, ElementTextDirection.auto);
      expect(note.sizing, TextSizing.autoHeight);
      expect(contents.where((content) => content.canOwnChildren), hasLength(2));
      expect(strokeStyle.color, 0x80336699);
      expect(strokeStyle.width, 2.5);
    },
  );

  test(
    'document and stroke collections take immutable defensive snapshots',
    () {
      final points = [Point2.zero];
      final stroke = StrokeElementContent(points: points, style: strokeStyle);
      points.add(Point2(100, 100));
      expect(stroke.points, [Point2.zero]);
      expect(() => stroke.points.add(Point2(1, 1)), throwsUnsupportedError);
      final source = [element('group'), element('child', parent: 'group')];
      final board = document(source);
      source.clear();
      expect(board.elements, hasLength(2));
      expect(() => board.elements.clear(), throwsUnsupportedError);
      expect(() => board.preorder.clear(), throwsUnsupportedError);
      expect(() => board.byId.clear(), throwsUnsupportedError);
      expect(() => board.children.clear(), throwsUnsupportedError);
      expect(
        () => board.childrenOf(ElementId('group')).clear(),
        throwsUnsupportedError,
      );
      expect(() => board.childrenOf(null).clear(), throwsUnsupportedError);
      expect(
        () => board.childrenOf(ElementId('missing')).add(element('extra')),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'source occurrence determines sibling order and contiguous subtree preorder',
    () {
      final board = document([
        element(
          'nested-leaf',
          parent: 'nested',
          content: ImageElementContent(assetId: 'asset', bounds: box),
        ),
        element('first-root'),
        element('frame-child', parent: 'frame'),
        element(
          'frame',
          parent: 'first-root',
          content: ContainerFrameElementContent(bounds: box),
        ),
        element('second-root'),
        element('last-child', parent: 'first-root'),
        element('nested', parent: 'frame'),
      ]);
      expect(board.childrenOf(null).map((entry) => entry.id.value), [
        'first-root',
        'second-root',
      ]);
      expect(
        board
            .childrenOf(ElementId('first-root'))
            .map((entry) => entry.id.value),
        ['frame', 'last-child'],
      );
      expect(board.preorder.map((entry) => entry.id.value), [
        'first-root',
        'frame',
        'frame-child',
        'nested',
        'nested-leaf',
        'last-child',
        'second-root',
      ]);
      expect(board.byId[ElementId('nested-leaf')], same(board.elements.first));
    },
  );

  test(
    'only groups and container frames own children, independent of their area',
    () {
      final board = document([
        element(
          'container',
          content: ContainerFrameElementContent(bounds: box),
        ),
        element(
          'outside',
          parent: 'container',
          transform: Transform2.translation(1e9, -1e9),
        ),
        element('group', parent: 'outside'),
        element(
          'nested-container',
          parent: 'group',
          content: ContainerFrameElementContent(bounds: box),
        ),
        element(
          'export',
          parent: 'nested-container',
          content: ExportFrameElementContent(bounds: box),
        ),
      ]);
      expect(
        board.byId[ElementId('outside')]!.parentId,
        ElementId('container'),
      );
      expect(board.byId[ElementId('outside')]!.transform.tx, 1e9);
      for (final content in <ElementContent>[
        ExportFrameElementContent(bounds: box),
        ImageElementContent(assetId: 'asset', bounds: box),
        TextElementContent(text: '', bounds: box, style: textStyle),
        StickyNoteElementContent(
          text: '',
          bounds: box,
          style: textStyle,
          backgroundColor: 0xffffffff,
        ),
        ShapeElementContent(
          kind: ShapeKind.rectangle,
          bounds: box,
          fillColor: 0,
        ),
      ]) {
        expect(
          () => document([
            element('parent', content: content),
            element('child', parent: 'parent'),
          ]),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'invalid ownership graphs reject duplicates, orphans and all cycles',
    () {
      expect(
        () => document([element('same'), element('same')]),
        throwsArgumentError,
      );
      expect(
        () => document([element('child', parent: 'missing')]),
        throwsArgumentError,
      );
      expect(
        () => document([element('self', parent: 'self')]),
        throwsArgumentError,
      );
      expect(
        () => document([
          element('root'),
          element('a', parent: 'b'),
          element('b', parent: 'c'),
          element('c', parent: 'a'),
        ]),
        throwsArgumentError,
      );
      final empty = document([]);
      expect(empty.elements, isEmpty);
      expect(empty.preorder, isEmpty);
      expect(empty.childrenOf(null), isEmpty);
    },
  );

  test('deep ownership validates iteratively without recursive traversal', () {
    final board = document([
      for (var i = 4999; i >= 0; i--)
        element('g$i', parent: i == 0 ? null : 'g${i - 1}'),
    ]);
    expect(board.preorder, hasLength(5000));
    expect(board.preorder.first.id, ElementId('g0'));
    expect(board.preorder.last.id, ElementId('g4999'));
  });

  test(
    'document version and revision are supplied and never silently advanced',
    () {
      final board = BoardDocument(id: 'original', revision: 42, elements: []);
      expect(board.id, 'original');
      expect(board.revision, 42);
      expect(board.schemaVersion, BoardDocument.currentVersion);
      expect(BoardDocument.currentVersion, 1);
      for (final revision in [-1, -100]) {
        expect(
          () => BoardDocument(id: 'board', revision: revision, elements: []),
          throwsArgumentError,
        );
      }
      for (final version in [-1, 0, 2]) {
        expect(
          () => BoardDocument(
            id: 'board',
            revision: 0,
            schemaVersion: version,
            elements: [],
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => BoardDocument(id: ' \t', revision: 0, elements: []),
        throwsArgumentError,
      );
    },
  );

  test(
    'element revisions are caller controlled and portable with their document',
    () {
      final original = DocumentElement(
        id: ElementId('original'),
        parentId: ElementId('parent'),
        content: const GroupElementContent(),
      );
      expect(original.revision, 0);
      final edited = original.copyWith(revision: 7, locked: true);
      expect(edited.id, same(original.id));
      expect(edited.parentId, same(original.parentId));
      expect(edited.revision, 7);
      expect(original.revision, 0);
      expect(
        edited.copyWith(transform: Transform2.translation(3, 4)).revision,
        7,
      );
      expect(edited.copyWith(revision: 0).revision, 0);
      final latest = edited.copyWith(revision: maximumDocumentRevision);
      final board = BoardDocument(
        id: 'maximum',
        revision: maximumDocumentRevision,
        elements: [element('parent'), latest],
      );
      expect(board.revision, maximumDocumentRevision);
      expect(board.byId[latest.id]!.revision, maximumDocumentRevision);
      expect(
        () => BoardDocument(
          id: 'older',
          revision: maximumDocumentRevision - 1,
          elements: [element('parent'), latest],
        ),
        throwsArgumentError,
      );
      expect(
        () => BoardDocument(
          id: 'older',
          revision: 6,
          elements: [element('parent'), edited],
        ),
        throwsArgumentError,
      );
      for (final revision in [-1, maximumDocumentRevision + 1]) {
        expect(
          () => original.copyWith(revision: revision),
          throwsArgumentError,
        );
        expect(
          () => BoardDocument(id: 'invalid', revision: revision, elements: []),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'general element opacity is finite, bounded and preserved on replacement',
    () {
      final original = element('group');
      expect(original.opacity, 1);
      final translucent = original.copyWith(opacity: 0.25);
      expect(translucent.opacity, 0.25);
      expect(translucent.id, same(original.id));
      expect(translucent.content, same(original.content));
      expect(translucent.copyWith(locked: true).opacity, 0.25);
      expect(translucent.copyWith(opacity: 0).opacity, 0);
      expect(translucent.copyWith(opacity: 1).opacity, 1);
      expect(original.opacity, 1);
      for (final opacity in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -0.01,
        1.01,
      ]) {
        expect(() => original.copyWith(opacity: opacity), throwsArgumentError);
      }
    },
  );

  test('content styles and local extents reject invalid values at runtime', () {
    for (final value in [double.nan, double.infinity, -1.0, 0.0]) {
      expect(() => StrokeStyle(color: 0, width: value), throwsArgumentError);
      expect(
        () => ElementTextStyle(fontId: 'font', fontSize: value, color: 0),
        throwsArgumentError,
      );
      expect(
        () => ArrowElementContent(
          start: Point2.zero,
          end: Point2(1, 0),
          style: strokeStyle,
          headLength: value,
          headWidth: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => ArrowElementContent(
          start: Point2.zero,
          end: Point2(1, 0),
          style: strokeStyle,
          headLength: 1,
          headWidth: value,
        ),
        throwsArgumentError,
      );
    }
    for (final color in [-1, 0x100000000]) {
      expect(() => StrokeStyle(color: color, width: 1), throwsArgumentError);
      expect(
        () => ElementTextStyle(fontId: 'font', fontSize: 1, color: color),
        throwsArgumentError,
      );
      expect(
        () => ShapeElementContent(
          kind: ShapeKind.ellipse,
          bounds: box,
          fillColor: color,
        ),
        throwsArgumentError,
      );
      expect(
        () => StickyNoteElementContent(
          text: '',
          bounds: box,
          style: textStyle,
          backgroundColor: color,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => ElementTextStyle(fontId: ' ', fontSize: 10, color: 0),
      throwsArgumentError,
    );
    expect(
      () => ImageElementContent(assetId: '', bounds: box),
      throwsArgumentError,
    );
    expect(
      () => ShapeElementContent(kind: ShapeKind.triangle, bounds: box),
      throwsArgumentError,
    );
    expect(
      () => StrokeElementContent(points: [], style: strokeStyle),
      throwsArgumentError,
    );
    expect(
      () => StrokeElementContent(
        points: [Point2(-1e308, 0), Point2(1e308, 0)],
        style: strokeStyle,
      ),
      throwsArgumentError,
    );
    expect(
      () => LineElementContent(
        start: Point2.zero,
        end: Point2.zero,
        style: strokeStyle,
      ),
      throwsArgumentError,
    );
    expect(
      () => ArrowElementContent(
        start: Point2.zero,
        end: Point2.zero,
        style: strokeStyle,
        headLength: 1,
        headWidth: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => LineElementContent(
        start: Point2(-1e308, 0),
        end: Point2(1e308, 0),
        style: strokeStyle,
      ),
      throwsArgumentError,
    );
    for (final empty in [Bounds2(0, 0, 0, 1), Bounds2(0, 0, 1, 0)]) {
      for (final create in <ElementContent Function()>[
        () => ShapeElementContent(
          kind: ShapeKind.rectangle,
          bounds: empty,
          fillColor: 0,
        ),
        () => TextElementContent(text: '', bounds: empty, style: textStyle),
        () => StickyNoteElementContent(
          text: '',
          bounds: empty,
          style: textStyle,
          backgroundColor: 0,
        ),
        () => ImageElementContent(assetId: 'asset', bounds: empty),
        () => ExportFrameElementContent(bounds: empty),
        () => ContainerFrameElementContent(bounds: empty),
      ]) {
        expect(create, throwsArgumentError);
      }
    }
  });
}
