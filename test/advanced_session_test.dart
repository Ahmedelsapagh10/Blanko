import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/document_geometry.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

ElementId id(String value) => ElementId(value);
DocumentElement element(
  String value, {
  String? parent,
  bool locked = false,
  Transform2 transform = Transform2.identity,
  ElementContent? content,
  double opacity = 1,
}) => DocumentElement(
  id: id(value),
  parentId: parent == null ? null : id(parent),
  locked: locked,
  transform: transform,
  opacity: opacity,
  content:
      content ??
      ShapeElementContent(
        kind: ShapeKind.rectangle,
        bounds: Bounds2(0, 0, 10, 10),
        fillColor: 0xff000000,
      ),
);
BoardSession session(
  List<DocumentElement> elements, {
  List<DocumentAssetReference>? assets,
}) => BoardSession(
  document: BoardDocument(
    id: 'advanced',
    revision: 0,
    elements: elements,
    assets: assets ?? [],
    fontReferences: [],
  ),
);
List<String> order(BoardSession s) =>
    s.document.elements.map((e) => e.id.value).toList();
void expectWorld(
  BoardDocument document,
  ElementId target,
  Transform2 expected,
) {
  final geometry = DocumentGeometry(document);
  for (final point in [Point2.zero, Point2(1, 2)]) {
    final actual = geometry.localToWorld(target, point),
        wanted = expected.apply(point);
    expect(actual.x, closeTo(wanted.x, 1e-8));
    expect(actual.y, closeTo(wanted.y, 1e-8));
  }
}

final frame = ContainerFrameElementContent(
  bounds: Bounds2(0, 0, 300, 200),
  label: 'Owner',
);
void main() {
  test(
    'multi transform normalizes owners and keeps nested local transforms, one undo',
    () {
      final s = session([
        element('owner', content: frame, transform: Transform2.rotation(.5)),
        element(
          'child',
          parent: 'owner',
          transform: Transform2.translation(30, 40),
        ),
        element('other', transform: Transform2.translation(80, 0)),
      ]);
      final before = s.document, geometry = DocumentGeometry(before);
      final delta = Transform2.translation(12, 24) * Transform2.rotation(.2);
      expect(s.selectionRoots([id('child'), id('owner'), id('other')]), [
        id('owner'),
        id('other'),
      ]);
      expect(
        s.transformMany([id('child'), id('owner'), id('other')], delta),
        isTrue,
      );
      expect(s.document.revision, 1);
      expect(
        s.document.byId[id('child')]!.transform,
        before.byId[id('child')]!.transform,
      );
      for (final target in before.byId.keys) {
        expectWorld(
          s.document,
          target,
          delta * geometry.worldTransformOf(target),
        );
      }
      expect(s.undo(), isTrue);
      for (final target in before.byId.keys) {
        expectWorld(s.document, target, geometry.worldTransformOf(target));
      }
      expect(s.canUndo, isFalse);
      expect(s.redo(), isTrue);
      expect(s.document.revision, 3);
    },
  );
  test('individual world translations are atomic through rotated parents', () {
    final s = session([
      element('owner', content: frame, transform: Transform2.rotation(.7)),
      element('a', parent: 'owner'),
      element('b'),
    ]);
    final old = DocumentGeometry(s.document);
    expect(
      s.translateMany({id('a'): Point2(20, -10), id('b'): Point2(-5, 6)}),
      isTrue,
    );
    expectWorld(
      s.document,
      id('a'),
      Transform2.translation(20, -10) * old.worldTransformOf(id('a')),
    );
    expectWorld(
      s.document,
      id('b'),
      Transform2.translation(-5, 6) * old.worldTransformOf(id('b')),
    );
    expect(s.document.revision, 1);
    expect(s.undo(), isTrue);
    expect(s.canUndo, isFalse);
  });
  test(
    'unknown or locked subtree rejects whole transform/delete without partial mutation',
    () {
      final s = session([
        element('owner', content: frame),
        element('child', parent: 'owner', locked: true),
        element('other'),
      ]);
      final before = s.document;
      expect(s.canEdit(id('owner')), isFalse);
      expect(
        s.transformMany([
          id('owner'),
          id('other'),
        ], Transform2.translation(1, 1)),
        isFalse,
      );
      expect(
        s.translateMany({id('owner'): Point2(2, 2), id('other'): Point2(1, 1)}),
        isFalse,
      );
      expect(s.deleteMany([id('owner'), id('other')]), isFalse);
      expect(
        s.transformMany([
          id('other'),
          id('missing'),
        ], Transform2.translation(1, 1)),
        isFalse,
      );
      expect(s.document, same(before));
      expect(s.canUndo, isFalse);
    },
  );
  test(
    'bulk delete removes normalized forest and undo restores exact order/ownership',
    () {
      final s = session([
        element('owner', content: frame),
        element('a', parent: 'owner'),
        element('b'),
        element('c'),
      ]);
      final before = order(s);
      expect(s.deleteMany([id('owner'), id('a'), id('b')]), isTrue);
      expect(order(s), ['c']);
      expect(s.document.revision, 1);
      expect(s.undo(), isTrue);
      expect(order(s), before);
      expect(s.document.byId[id('a')]!.parentId, id('owner'));
      expect(s.redo(), isTrue);
      expect(order(s), ['c']);
    },
  );
  test(
    'multi duplicate preserves owner boundaries, asset refs and forest with fresh IDs',
    () {
      final asset = DocumentAssetReference(
        id: 'original',
        mimeType: 'image/png',
        pixelWidth: 2,
        pixelHeight: 2,
        byteLength: 16,
      );
      final s = session(
        [
          element('owner', content: frame, transform: Transform2.rotation(.3)),
          element(
            'group',
            parent: 'owner',
            content: const GroupElementContent(),
            transform: Transform2.translation(20, 10),
          ),
          element(
            'image',
            parent: 'group',
            content: ImageElementContent(
              assetId: 'original',
              bounds: Bounds2(0, 0, 2, 2),
            ),
          ),
          element('other'),
        ],
        assets: [asset],
      );
      final before = s.document, geometry = DocumentGeometry(before);
      final roots = s.duplicateMany([id('group'), id('image'), id('other')]);
      expect(roots.length, 2);
      expect(s.document.elements.length, 7);
      expect(s.document.byId[roots.first]!.parentId, id('owner'));
      final imageCopy = s.document.childrenOf(roots.first).single;
      expect((imageCopy.content as ImageElementContent).assetId, 'original');
      expect(s.document.assets!.length, 1);
      expectWorld(
        s.document,
        imageCopy.id,
        Transform2.translation(24, 24) * geometry.worldTransformOf(id('image')),
      );
      expect(s.document.revision, 1);
      s.undo();
      expect(order(s), before.elements.map((e) => e.id.value).toList());
      s.redo();
      expect(s.document.byId.containsKey(roots.first), isTrue);
    },
  );
  test(
    'group siblings at frontmost selected layer and undo preserves exact source order',
    () {
      final s = session([
        element('a'),
        element('middle'),
        element('b'),
        element('top'),
      ]);
      final before = s.document;
      final group = s.group([id('a'), id('b')]);
      expect(group, isNotNull);
      expect(s.document.childrenOf(null).map((e) => e.id), [
        id('middle'),
        group!,
        id('top'),
      ]);
      expect(s.document.childrenOf(group).map((e) => e.id), [id('a'), id('b')]);
      expectWorld(s.document, id('a'), Transform2.identity);
      expectWorld(s.document, id('b'), Transform2.identity);
      s.undo();
      expect(order(s), before.elements.map((e) => e.id.value));
      s.redo();
      expect(s.document.childrenOf(group).length, 2);
    },
  );
  test('cross-frame and locked grouping are rejected atomically', () {
    final s = session([
      element('one', content: frame),
      element('a', parent: 'one'),
      element('two', content: frame),
      element('b', parent: 'two'),
      element('c', locked: true),
    ]);
    final before = s.document;
    expect(s.canGroup([id('a'), id('b')]), isFalse);
    expect(s.group([id('a'), id('b')]), isNull);
    expect(s.group([id('one'), id('c')]), isNull);
    expect(s.document, same(before));
  });
  test(
    'ungroup composes parent transforms and opacity, retaining IDs and layer',
    () {
      final s = session([
        element('below'),
        element(
          'g',
          content: const GroupElementContent(),
          transform: Transform2.rotation(.5),
          opacity: .5,
        ),
        element(
          'a',
          parent: 'g',
          transform: Transform2.translation(10, 20),
          opacity: .6,
        ),
        element('b', parent: 'g'),
        element('above'),
      ]);
      final old = s.document, geo = DocumentGeometry(old);
      expect(s.ungroup([id('g')]), [id('a'), id('b')]);
      expect(order(s), ['below', 'a', 'b', 'above']);
      expectWorld(s.document, id('a'), geo.worldTransformOf(id('a')));
      expect(s.document.byId[id('a')]!.opacity, closeTo(.3, 1e-8));
      expect(s.document.byId[id('a')]!.parentId, isNull);
      expect(s.document.revision, 1);
      s.undo();
      expect(order(s), old.elements.map((e) => e.id.value));
      expect(s.document.byId[id('a')]!.opacity, .6);
      expect(s.ungroup([id('below')]), isEmpty);
    },
  );
  test(
    'nested group ungroup retains inner hierarchy and frames are never ungrouped',
    () {
      final s = session([
        element(
          'outer',
          content: const GroupElementContent(),
          transform: Transform2.translation(20, 0),
        ),
        element('inner', parent: 'outer', content: const GroupElementContent()),
        element('child', parent: 'inner'),
        element('frame', content: frame),
      ]);
      final world = DocumentGeometry(s.document).worldTransformOf(id('child'));
      expect(s.ungroup([id('outer'), id('inner')]), [id('inner')]);
      expectWorld(s.document, id('child'), world);
      expect(s.document.byId[id('child')]!.parentId, id('inner'));
      expect(s.ungroup([id('frame')]), isEmpty);
    },
  );
  test('lock state is undoable and inherited locks cannot be bypassed', () {
    final s = session([
      element('g', content: const GroupElementContent()),
      element('a', parent: 'g'),
      element('b'),
    ]);
    expect(s.setLockedMany([id('g'), id('b')], true), isTrue);
    expect(s.document.revision, 1);
    expect(s.canEdit(id('a')), isFalse);
    expect(s.setLockedMany([id('a')], false), isFalse);
    expect(s.deleteMany([id('a')]), isFalse);
    final restored = DocumentCodec.decode(DocumentCodec.encode(s.document));
    expect(restored.byId[id('g')]!.locked, isTrue);
    s.undo();
    expect(s.canEdit(id('a')), isTrue);
    s.redo();
    expect(s.setLockedMany([id('g'), id('b')], false), isTrue);
    expect(s.canEdit(id('a')), isTrue);
  });
  test('stacking preserves selected order per parent and exact undo order', () {
    final s = session([
      element('a'),
      element('b'),
      element('c'),
      element('d'),
      element('owner', content: frame),
      element('x', parent: 'owner'),
      element('y', parent: 'owner'),
    ]);
    final before = order(s);
    expect(s.reorderMany([id('a'), id('c'), id('x')], 'front'), isTrue);
    expect(s.document.childrenOf(null).map((e) => e.id), [
      id('b'),
      id('d'),
      id('owner'),
      id('a'),
      id('c'),
    ]);
    expect(s.document.childrenOf(id('owner')).map((e) => e.id), [
      id('y'),
      id('x'),
    ]);
    expect(s.document.revision, 1);
    s.undo();
    expect(order(s), before);
    s.redo();
    expect(s.document.byId[id('x')]!.parentId, id('owner'));
  });
  test(
    'one-step stacking moves selected blocks without reversing relative order',
    () {
      final s = session([
        element('a'),
        element('b'),
        element('c'),
        element('d'),
      ]);
      expect(s.reorderMany([id('a'), id('b')], 'forward'), isTrue);
      expect(order(s), ['c', 'a', 'b', 'd']);
      expect(s.reorderMany([id('a'), id('b')], 'backward'), isTrue);
      expect(order(s), ['a', 'b', 'c', 'd']);
      expect(s.reorderMany([id('c'), id('d')], 'back'), isTrue);
      expect(order(s), ['c', 'd', 'a', 'b']);
    },
  );
  test(
    'fragment paste makes fresh IDs, carries declarations and undoes atomically',
    () {
      final s = session([element('element-1')]);
      final asset = DocumentAssetReference(
        id: 'fresh-image',
        mimeType: 'image/png',
        pixelWidth: 2,
        pixelHeight: 2,
        byteLength: 16,
      );
      final fragment = BoardDocument(
        id: 'fragment',
        revision: 0,
        assets: [asset],
        fontReferences: [],
        elements: [
          element(
            'element-1',
            content: const GroupElementContent(),
            transform: Transform2.translation(100, 200),
          ),
          element(
            'image',
            parent: 'element-1',
            content: ImageElementContent(
              assetId: 'fresh-image',
              bounds: Bounds2(0, 0, 2, 2),
            ),
          ),
        ],
      );
      final inserted = s.insertFragment(fragment, offset: Point2(24, 24));
      expect(inserted.length, 1);
      expect(inserted.single, id('element-2'));
      final image = s.document.childrenOf(inserted.single).single;
      expectWorld(s.document, image.id, Transform2.translation(124, 224));
      expect(s.document.assets!.single.id, 'fresh-image');
      expect(s.document.revision, 1);
      s.undo();
      expect(order(s), ['element-1']);
      expect(s.document.assets!.single.id, 'fresh-image');
      s.redo();
      expect(s.document.childrenOf(inserted.single).single.id, image.id);
    },
  );
  test('fragment manifest collision leaves document/history unchanged', () {
    final s = session(
      [element('a')],
      assets: [
        DocumentAssetReference(
          id: 'image',
          mimeType: 'image/png',
          pixelWidth: 2,
          pixelHeight: 2,
          byteLength: 16,
        ),
      ],
    );
    final before = s.document;
    final bad = BoardDocument(
      id: 'fragment',
      revision: 0,
      elements: [element('b')],
      assets: [
        DocumentAssetReference(
          id: 'image',
          mimeType: 'image/png',
          pixelWidth: 3,
          pixelHeight: 2,
          byteLength: 16,
        ),
      ],
      fontReferences: [],
    );
    expect(
      () => s.insertFragment(bad, offset: Point2.zero),
      throwsArgumentError,
    );
    expect(s.document, same(before));
    expect(s.canUndo, isFalse);
    expect(s.transformMany([id('a')], Transform2.identity), isFalse);
    expect(s.document, same(before));
  });
  test('multi-transform overflow preserves every element and redo history', () {
    final s = session([
      element('a'),
      element('huge', transform: Transform2.translation(1e308, 0)),
    ]);
    s.translateMany({id('a'): Point2(1, 0)});
    s.undo();
    final before = s.document;
    expect(
      () => s.transformMany([
        id('a'),
        id('huge'),
      ], Transform2.translation(1e308, 0)),
      throwsArgumentError,
    );
    expect(s.document, same(before));
    expect(s.canRedo, isTrue);
    expect(
      () => s.translateMany({
        id('a'): Point2(2, 0),
        id('huge'): Point2(1e308, 0),
      }),
      throwsArgumentError,
    );
    expect(s.document, same(before));
    expect(s.canRedo, isTrue);
  });
  test(
    'fragment fonts merge, reject collisions and remain available for undo',
    () {
      final font = DocumentFontReference(id: 'arabic', family: 'Noto Arabic');
      final s = BoardSession(
        document: BoardDocument(
          id: 'font-receiver',
          revision: 0,
          elements: [],
          assets: [],
          fontReferences: [font],
        ),
      );
      final fragment = BoardDocument(
        id: 'font-fragment',
        revision: 0,
        elements: [element('a')],
        assets: [],
        fontReferences: [
          DocumentFontReference(id: 'arabic', family: 'Noto Arabic'),
          DocumentFontReference(id: 'new', family: 'Noto Sans'),
        ],
      );
      s.insertFragment(fragment, offset: Point2.zero);
      expect(s.document.fontReferences!.map((font) => font.id), [
        'arabic',
        'new',
      ]);
      s.undo();
      expect(s.document.fontReferences!.map((font) => font.id), [
        'arabic',
        'new',
      ]);
      final before = s.document;
      final conflicting = BoardDocument(
        id: 'bad-font',
        revision: 0,
        elements: [element('b')],
        assets: [],
        fontReferences: [
          DocumentFontReference(id: 'arabic', family: 'Different'),
        ],
      );
      expect(
        () => s.insertFragment(conflicting, offset: Point2.zero),
        throwsArgumentError,
      );
      expect(s.document, same(before));
      expect(s.canRedo, isTrue);
    },
  );
}
