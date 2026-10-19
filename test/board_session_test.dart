import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_geometry.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

ShapeElementContent shape() => ShapeElementContent(
  kind: ShapeKind.rectangle,
  bounds: Bounds2(0, 0, 100, 50),
  fillColor: 0xff663399,
);

DocumentElement entry(
  String id, {
  String? parent,
  bool locked = false,
  Transform2 transform = Transform2.identity,
}) => DocumentElement(
  id: ElementId(id),
  parentId: parent == null ? null : ElementId(parent),
  content: const GroupElementContent(),
  locked: locked,
  transform: transform,
);

void main() {
  test(
    'insert, move and delete undo and redo preserve immutable snapshots',
    () {
      final session = BoardSession();
      final empty = session.document;
      final content = shape();
      final id = session.insert(content);
      final inserted = session.document;
      expect(session.canUndo, isTrue);
      expect(session.canRedo, isFalse);
      expect(session.translate(id, Point2(20, -7)), isTrue);
      final moved = session.document;
      expect(moved.byId[id]!.transform, Transform2.translation(20, -7));
      expect(session.delete(id), isTrue);
      expect(session.document.elements, isEmpty);
      expect(session.undo(), isTrue);
      expect(
        session.document.byId[id]!.transform,
        Transform2.translation(20, -7),
      );
      expect(session.undo(), isTrue);
      expect(session.document.byId[id]!.transform, Transform2.identity);
      expect(session.undo(), isTrue);
      expect(session.document.elements, isEmpty);
      expect(session.undo(), isFalse);
      expect(session.redo(), isTrue);
      expect(session.redo(), isTrue);
      expect(session.redo(), isTrue);
      expect(session.redo(), isFalse);
      expect(session.document.revision, 9);
      expect(empty.elements, isEmpty);
      expect(inserted.byId[id]!.transform, Transform2.identity);
      expect(inserted.byId[id]!.revision, 1);
      expect(moved.byId[id]!.revision, 2);
      expect(moved.byId[id]!.content, same(content));
      expect(() => moved.elements.clear(), throwsUnsupportedError);
    },
  );

  test('new edit clears redo and never recycles an undone identity', () {
    final session = BoardSession();
    final first = session.insert(shape());
    session.undo();
    final second = session.insert(shape());
    expect(second, isNot(first));
    expect(session.canRedo, isFalse);
    expect(session.redo(), isFalse);
    expect(session.document.elements.single.id, second);
    final loaded = BoardSession(
      document: BoardDocument(
        id: 'loaded',
        revision: 0,
        elements: [entry('element-1'), entry('element-2')],
      ),
    );
    loaded.delete(ElementId('element-1'));
    expect(loaded.insert(shape()), ElementId('element-3'));
  });

  test(
    'bounded inverse history retains only the configured recent changes',
    () {
      final session = BoardSession(historyLimit: 2);
      final first = session.insert(shape());
      session.insert(shape());
      session.insert(shape());
      expect(session.undo(), isTrue);
      expect(session.undo(), isTrue);
      expect(session.undo(), isFalse);
      expect(session.document.elements.single.id, first);
      expect(session.redo(), isTrue);
      expect(session.redo(), isTrue);
      final noHistory = BoardSession(historyLimit: 0);
      noHistory.insert(shape());
      expect(noHistory.canUndo, isFalse);
      expect(noHistory.undo(), isFalse);
      expect(() => BoardSession(historyLimit: -1), throwsArgumentError);
    },
  );

  test('world movement respects rotated and scaled ownership transforms', () {
    final parent = entry(
      'parent',
      transform: Transform2(a: 0, b: 2, c: -3, d: 0),
    );
    final child = entry(
      'child',
      parent: 'parent',
      transform: Transform2.translation(4, 5),
    );
    final session = BoardSession(
      document: BoardDocument(
        id: 'nested',
        revision: 0,
        elements: [child, parent],
      ),
    );
    final original = DocumentGeometry(
      session.document,
    ).localToWorld(child.id, Point2.zero);
    expect(session.translate(child.id, Point2(30, 8)), isTrue);
    final moved = DocumentGeometry(
      session.document,
    ).localToWorld(child.id, Point2.zero);
    expect(moved, original + Point2(30, 8));
    expect(session.document.byId[parent.id], same(parent));
    session.undo();
    expect(session.document.byId[child.id]!.transform, child.transform);
    session.redo();
    expect(
      DocumentGeometry(session.document).localToWorld(child.id, Point2.zero),
      moved,
    );
  });

  test(
    'subtree delete restores unusual source and sibling order atomically',
    () {
      final source = [
        entry('child-b', parent: 'group'),
        entry('root-a'),
        entry('grandchild', parent: 'child-a'),
        entry('group'),
        entry('child-a', parent: 'group'),
        entry('root-z'),
      ];
      final session = BoardSession(
        document: BoardDocument(id: 'ordered', revision: 0, elements: source),
      );
      session.delete(ElementId('group'));
      expect(session.document.elements.map((entry) => entry.id.value), [
        'root-a',
        'root-z',
      ]);
      session.undo();
      expect(
        session.document.elements.map((entry) => entry.id),
        source.map((entry) => entry.id),
      );
      expect(session.document.preorder.map((entry) => entry.id.value), [
        'root-a',
        'group',
        'child-b',
        'child-a',
        'grandchild',
        'root-z',
      ]);
      expect(session.document.byId[ElementId('group')]!.revision, 2);
      session.redo();
      expect(session.document.elements.map((entry) => entry.id.value), [
        'root-a',
        'root-z',
      ]);
    },
  );

  test(
    'missing, zero displacement and locked operations do not consume history',
    () {
      final session = BoardSession(
        document: BoardDocument(
          id: 'locks',
          revision: 0,
          elements: [
            entry('locked', locked: true),
            entry('child', parent: 'locked'),
            entry('group'),
            entry('locked-child', parent: 'group', locked: true),
          ],
        ),
      );
      final before = session.document;
      expect(session.translate(ElementId('missing'), Point2(1, 1)), isFalse);
      expect(session.delete(ElementId('missing')), isFalse);
      expect(session.translate(ElementId('locked'), Point2(1, 1)), isFalse);
      expect(session.translate(ElementId('child'), Point2(1, 1)), isFalse);
      expect(session.delete(ElementId('child')), isFalse);
      expect(session.delete(ElementId('group')), isFalse);
      expect(session.translate(ElementId('group'), Point2(1, 1)), isFalse);
      expect(session.translate(ElementId('group'), Point2.zero), isFalse);
      expect(session.document, same(before));
      expect(session.canUndo, isFalse);
      final id = session.insert(shape());
      session.undo();
      expect(session.translate(id, Point2.zero), isFalse);
      expect(session.canRedo, isTrue);
    },
  );

  test('settings and authoritative manifests survive changes and undo', () {
    final asset = DocumentAssetReference(
      id: 'image',
      mimeType: 'image/png',
      pixelWidth: 8,
      pixelHeight: 8,
    );
    final font = DocumentFontReference(id: 'font', family: 'Family');
    final settings = CanvasSettings(
      backgroundColor: 0xffeeeeee,
      grid: GridSettings(visible: true),
    );
    final metadata = DocumentMetadata(
      createdAt: DateTime.utc(2020),
      modifiedAt: DateTime.utc(2021),
    );
    final session = BoardSession(
      document: BoardDocument(
        id: 'metadata',
        revision: 12,
        title: 'Board title',
        workspaceId: 'workspace',
        canvasSettings: settings,
        metadata: metadata,
        assets: [asset],
        fontReferences: [font],
        elements: [],
      ),
    );
    final id = session.insert(shape());
    session.translate(id, Point2(4, 5));
    session.undo();
    final board = session.document;
    expect(board.id, 'metadata');
    expect(board.title, 'Board title');
    expect(board.workspaceId, 'workspace');
    expect(board.revision, 15);
    expect(board.canvasSettings, same(settings));
    expect(board.metadata, same(metadata));
    expect(board.assets!.single, same(asset));
    expect(board.fontReferences!.single, same(font));
  });

  test('invalid inserts and overflows preserve document and redo branch', () {
    final session = BoardSession(
      document: BoardDocument(
        id: 'atomic',
        revision: 0,
        elements: [],
        assets: [],
      ),
    );
    final id = session.insert(
      shape(),
      transform: Transform2.translation(1e308, 0),
    );
    session.insert(shape());
    session.undo();
    final before = session.document;
    expect(
      () => session.insert(
        ImageElementContent(assetId: 'missing', bounds: Bounds2(0, 0, 1, 1)),
      ),
      throwsArgumentError,
    );
    expect(session.document, same(before));
    expect(session.canRedo, isTrue);
    expect(() => session.translate(id, Point2(1e308, 0)), throwsArgumentError);
    expect(session.document, same(before));
    expect(session.canRedo, isTrue);
    session.redo();
    expect(session.document.elements, hasLength(2));
  });

  test('revision exhaustion fails atomically including undo', () {
    final session = BoardSession(
      document: BoardDocument(
        id: 'max',
        revision: maximumDocumentRevision - 1,
        elements: [],
      ),
    );
    session.insert(shape());
    final before = session.document;
    expect(() => session.undo(), throwsStateError);
    expect(() => session.insert(shape()), throwsStateError);
    expect(session.document, same(before));
    expect(session.canUndo, isTrue);
    expect(session.canRedo, isFalse);
  });
  test('batch replacement preserves source order, identities, locks and clear undo', () {
    final stroke = StrokeElementContent(points:[Point2.zero,Point2(100,0)],style:StrokeStyle(color:0xff123456,width:4));
    final session = BoardSession(document:BoardDocument(id:'batch',title:'Keep me',revision:0,elements:[
      DocumentElement(id:ElementId('a'),content:stroke,opacity:.4,transform:Transform2.translation(5,6)),
      entry('b'),entry('c'),entry('element-1',locked:true),
    ]));
    final original = session.document;
    expect(session.replaceElements({ElementId('a'):[stroke,stroke],ElementId('c'):[],ElementId('element-1'):[]}),true);
    final changed = session.document;
    expect(changed.elements.map((e)=>e.id.value),['a','element-2','b','element-1']);
    expect(changed.elements[1].opacity,.4);
    expect(changed.elements[1].transform,original.elements.first.transform);
    session.undo(); expect(session.document.elements.map((e)=>e.id),original.elements.map((e)=>e.id));
    session.redo(); expect(session.document.elements.map((e)=>e.id),changed.elements.map((e)=>e.id));
    expect(session.replaceElements({ElementId('element-1'):[]}),false);
    session.clearAll();expect(session.document.elements,isEmpty);expect(session.document.title,'Keep me');
    session.undo();expect(session.document.elements.map((e)=>e.id),changed.elements.map((e)=>e.id));
  });

}
