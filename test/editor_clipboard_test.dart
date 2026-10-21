import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_geometry.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/editor/editor_clipboard.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'support/image_test_bytes.dart';
import 'support/test_board_store.dart';

final frameId = ElementId('frame'), groupId = ElementId('group');
final imageId = ElementId('image'), textId = ElementId('text');
final shapeId = ElementId('shape');

BoardDocument fixture({int? declaredLength}) => BoardDocument(
  id: 'source',
  revision: 3,
  assets: [
    DocumentAssetReference(
      id: 'photo',
      mimeType: 'image/png',
      pixelWidth: 64,
      pixelHeight: 32,
      byteLength: declaredLength ?? imageTestPng().length,
    ),
  ],
  fontReferences: [
    DocumentFontReference(id: 'editor-sans-v1', family: 'Roboto'),
  ],
  elements: [
    DocumentElement(
      id: frameId,
      content: ContainerFrameElementContent(bounds: Bounds2(0, 0, 500, 500)),
      transform: Transform2.translation(100, 40) * Transform2.rotation(.3),
      opacity: .5,
    ),
    DocumentElement(
      id: groupId,
      parentId: frameId,
      content: const GroupElementContent(),
      transform: Transform2.translation(20, 30),
      opacity: .8,
    ),
    DocumentElement(
      id: imageId,
      parentId: groupId,
      content: ImageElementContent(
        assetId: 'photo',
        bounds: Bounds2(0, 0, 64, 32),
      ),
      transform: Transform2.translation(10, 15),
      locked: true,
    ),
    DocumentElement(
      id: textId,
      parentId: groupId,
      content: TextElementContent(
        text: 'مرحبا Blanko',
        bounds: Bounds2(0, 0, 120, 60),
        style: ElementTextStyle(
          fontId: 'editor-sans-v1',
          fontSize: 20,
          color: 0xff202d46,
        ),
      ),
      transform: Transform2.translation(80, 20),
    ),
    DocumentElement(
      id: shapeId,
      content: ShapeElementContent(
        kind: ShapeKind.rectangle,
        bounds: Bounds2(0, 0, 30, 30),
        fillColor: 0xff123456,
      ),
    ),
  ],
);

class _ReadGateStore extends TestBoardStore {
  final gate = Completer<Uint8List?>();
  bool reading = false;
  @override
  Future<Uint8List?> readAsset(String assetId) async {
    reading = true;
    return gate.future;
  }
}

class _WriteGateStore extends TestBoardStore {
  final gate = Completer<void>();
  bool staging = false;
  bool failAssets = false;
  @override
  Future<void> writeAsset(String assetId, Uint8List bytes) async {
    if (failAssets) throw StateError('Asset quota exceeded');
    staging = true;
    await gate.future;
    await super.writeAsset(assetId, bytes);
  }
}

void main() {
  test('embedded fonts get independent identities on every paste', () async {
    final clipboard = EditorClipboard();
    addTearDown(clipboard.dispose);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final store = TestBoardStore()..assets['font-original'] = bytes;
    final style = ElementTextStyle(
      fontId: 'custom-font',
      fontSize: 24,
      color: 0xff123456,
    );
    final source = BoardDocument(
      id: 'fonts',
      revision: 0,
      assets: [
        DocumentAssetReference(
          id: 'font-original',
          mimeType: 'font/ttf',
          byteLength: bytes.length,
        ),
      ],
      fontReferences: [
        DocumentFontReference(
          id: 'custom-font',
          family: 'Embedded',
          assetId: 'font-original',
        ),
      ],
      elements: [
        DocumentElement(
          id: textId,
          content: TextElementContent(
            text: 'مرحبا',
            bounds: Bounds2(0, 0, 120, 80),
            style: style,
            direction: ElementTextDirection.rtl,
            alignment: ElementTextAlignment.center,
            sizing: TextSizing.fixed,
          ),
        ),
        DocumentElement(
          id: shapeId,
          content: StickyNoteElementContent(
            text: 'note',
            bounds: Bounds2(0, 0, 160, 160),
            style: style,
            backgroundColor: 0xffffff00,
            alignment: ElementTextAlignment.end,
          ),
        ),
      ],
    );
    await clipboard.copy(source, [textId, shapeId], store);
    final first = await clipboard.preparePaste(store);
    final second = await clipboard.preparePaste(store);
    final firstFont = first.fontReferences!.single;
    final secondFont = second.fontReferences!.single;
    expect(firstFont.id, isNot('custom-font'));
    expect(secondFont.id, isNot(firstFont.id));
    expect(secondFont.assetId, isNot(firstFont.assetId));
    expect(store.assets[firstFont.assetId], orderedEquals(bytes));
    expect(store.assets[secondFont.assetId], orderedEquals(bytes));
    final text = first.byId[textId]!.content as TextElementContent;
    final note = first.byId[shapeId]!.content as StickyNoteElementContent;
    expect(text.style.fontId, firstFont.id);
    expect(note.style.fontId, firstFont.id);
    expect(text.style.fontSize, 24);
    expect(text.style.color, 0xff123456);
    expect(text.direction, ElementTextDirection.rtl);
    expect(text.alignment, ElementTextAlignment.center);
    expect(text.sizing, TextSizing.fixed);
    expect(note.backgroundColor, 0xffffff00);
    expect(note.alignment, ElementTextAlignment.end);
    expect(source.fontReferences!.single.id, 'custom-font');
    final session = BoardSession(document: source);
    session.insertFragment(first, offset: Point2(20, 20));
    session.insertFragment(second, offset: Point2(40, 40));
    expect(session.document.elements, hasLength(6));
    expect(session.document.fontReferences, hasLength(3));
    expect(session.undo(), isTrue);
    expect(session.document.elements, hasLength(4));
    expect(session.redo(), isTrue);
    expect(session.document.elements, hasLength(6));
  });

  test(
    'clipboard normalizes hierarchy, owns originals and stages independent cross-board assets',
    () async {
      final clipboard = EditorClipboard();
      addTearDown(clipboard.dispose);
      final source = TestBoardStore()..assets['photo'] = imageTestPng();
      final original = Uint8List.fromList(source.assets['photo']!);
      final document = fixture();
      final geometry = DocumentGeometry(document);
      await clipboard.copy(document, [groupId, imageId, groupId], source);
      expect(clipboard.hasContent, isTrue);
      source.assets['photo']![0] = 0;
      await source.deleteBoard('source');
      await source.deleteAsset('photo');
      await source.close();
      final target = TestBoardStore();
      final pasted = await clipboard.preparePaste(target);
      expect(pasted.elements.map((e) => e.id), [groupId, imageId, textId]);
      expect(pasted.byId[groupId]!.parentId, isNull);
      expect(
        pasted.byId[groupId]!.transform,
        geometry.worldTransformOf(groupId),
      );
      expect(pasted.byId[groupId]!.opacity, .4);
      expect(pasted.byId[imageId]!.parentId, groupId);
      expect(
        pasted.byId[imageId]!.transform,
        document.byId[imageId]!.transform,
      );
      expect(pasted.byId[imageId]!.locked, isTrue);
      expect(
        (pasted.byId[textId]!.content as TextElementContent).text,
        'مرحبا Blanko',
      );
      final asset =
          (pasted.byId[imageId]!.content as ImageElementContent).assetId;
      expect(asset, isNot('photo'));
      expect(target.assets[asset], original);
      expect(pasted.assets!.single.id, asset);
      expect(pasted.fontReferences!.single.id, 'editor-sans-v1');
      expect(target.writes, 0);
      expect(target.records, isEmpty);
      expect(target.last, isNull);
      final again = await clipboard.preparePaste(target);
      expect(again.assets!.single.id, isNot(asset));
      expect(target.assets[again.assets!.single.id], original);
    },
  );

  test(
    'copying a nested leaf preserves effective appearance and inherited protection',
    () async {
      final clipboard = EditorClipboard();
      addTearDown(clipboard.dispose);
      final document = fixture();
      final source = TestBoardStore()..assets['photo'] = imageTestPng();
      await clipboard.copy(document, [imageId], source);
      final pasted = await clipboard.preparePaste(TestBoardStore());
      final leaf = pasted.elements.single;
      expect(leaf.parentId, isNull);
      expect(leaf.locked, isTrue);
      expect(leaf.opacity, .4);
      expect(
        leaf.transform,
        DocumentGeometry(document).worldTransformOf(imageId),
      );
    },
  );

  test(
    'missing and oversized originals or stale IDs preserve the prior clipboard',
    () async {
      final clipboard = EditorClipboard();
      addTearDown(clipboard.dispose);
      await clipboard.copy(fixture(), [shapeId], null);
      await expectLater(
        clipboard.copy(fixture(), [imageId], TestBoardStore()),
        throwsStateError,
      );
      await expectLater(
        clipboard.copy(fixture(), [imageId], null),
        throwsStateError,
      );
      await expectLater(
        clipboard.copy(fixture(declaredLength: 17 * 1024 * 1024), [
          imageId,
        ], TestBoardStore()),
        throwsStateError,
      );
      await expectLater(
        clipboard.copy(fixture(), [ElementId('gone')], null),
        throwsStateError,
      );
      await expectLater(clipboard.copy(fixture(), [], null), throwsStateError);
      final result = await clipboard.preparePaste(null);
      expect(result.elements.single.id, shapeId);
      expect(result.assets, isEmpty);
    },
  );

  test(
    'a failed original length check leaves the clipboard unchanged',
    () async {
      final clipboard = EditorClipboard();
      addTearDown(clipboard.dispose);
      await clipboard.copy(fixture(), [shapeId], null);
      final bad = TestBoardStore()..assets['photo'] = Uint8List(3);
      await expectLater(
        clipboard.copy(fixture(), [imageId], bad),
        throwsStateError,
      );
      expect((await clipboard.preparePaste(null)).elements.single.id, shapeId);
    },
  );

  test(
    'late copy completion cannot replace a newer snapshot or revive disposed clipboard',
    () async {
      final clipboard = EditorClipboard();
      final blocked = _ReadGateStore();
      final old = clipboard.copy(fixture(), [imageId], blocked);
      final oldExpectation = expectLater(old, throwsStateError);
      await clipboard.copy(fixture(), [shapeId], null);
      blocked.gate.complete(imageTestPng());
      await oldExpectation;
      expect((await clipboard.preparePaste(null)).elements.single.id, shapeId);
      final second = _ReadGateStore();
      final pending = clipboard.copy(fixture(), [imageId], second);
      final pendingExpectation = expectLater(pending, throwsStateError);
      clipboard.dispose();
      second.gate.complete(imageTestPng());
      await pendingExpectation;
      expect(clipboard.hasContent, isFalse);
      await expectLater(clipboard.preparePaste(null), throwsStateError);
    },
  );

  test(
    'cancelled paste and failed asset writes never publish a destination board',
    () async {
      final clipboard = EditorClipboard();
      addTearDown(clipboard.dispose);
      await clipboard.copy(fixture(), [
        groupId,
      ], TestBoardStore()..assets['photo'] = imageTestPng());
      final untouched = TestBoardStore();
      await expectLater(
        clipboard.preparePaste(untouched, isCancelled: () => true),
        throwsStateError,
      );
      expect(untouched.assets, isEmpty);
      expect(untouched.writes, 0);
      final blocked = _WriteGateStore();
      var cancelled = false;
      final pending = clipboard.preparePaste(
        blocked,
        isCancelled: () => cancelled,
      );
      final expectation = expectLater(pending, throwsStateError);
      while (!blocked.staging) {
        await Future<void>.delayed(Duration.zero);
      }
      cancelled = true;
      blocked.gate.complete();
      await expectation;
      expect(blocked.records, isEmpty);
      expect(blocked.writes, 0);
      expect(blocked.last, isNull);
      final denied = _WriteGateStore()..failAssets = true;
      await expectLater(clipboard.preparePaste(denied), throwsStateError);
      expect(denied.records, isEmpty);
      expect(denied.assets, isEmpty);
      final readOnly = TestBoardStore()..readOnly = true;
      await expectLater(clipboard.preparePaste(readOnly), throwsStateError);
    },
  );

  test(
    'clear invalidates data and shape-only clipboard needs no storage',
    () async {
      final clipboard = EditorClipboard();
      addTearDown(clipboard.dispose);
      await clipboard.copy(fixture(), [shapeId], null);
      expect((await clipboard.preparePaste(null)).elements.single.id, shapeId);
      clipboard.clear();
      expect(clipboard.hasContent, isFalse);
      await expectLater(clipboard.preparePaste(null), throwsStateError);
    },
  );
}
