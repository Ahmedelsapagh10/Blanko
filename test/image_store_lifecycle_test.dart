import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/persistence/file_board_store.dart';
import 'package:whiteboard/src/viewport/camera.dart';

BoardSnapshot _snapshot(BoardDocument document, int generation) =>
    BoardSnapshot(
      document: document,
      camera: Camera(translation: Point2(-120, 48), zoom: 1.5),
      version: generation,
      savedAt: DateTime.utc(2026, 10, 20, 0, 0, generation),
    );

Future<Uint8List> _png() async {
  final data = await rootBundle.load(
    'assets/brand/icons/blanko_app_icon_dark_1024.png',
  );
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

BoardSession _session(Uint8List bytes) {
  final session = BoardSession(
    document: BoardDocument(
      id: 'original',
      revision: 0,
      elements: [],
      assets: [],
      fontReferences: [],
    ),
  );
  session.insert(
    ImageElementContent(assetId: 'shared-png', bounds: Bounds2(0, 0, 200, 200)),
    transform: Transform2.translation(-98.5, 450),
    asset: DocumentAssetReference(
      id: 'shared-png',
      mimeType: 'image/png',
      pixelWidth: 1024,
      pixelHeight: 1024,
      byteLength: bytes.length,
    ),
  );
  return session;
}

void main() {
  late Directory directory;
  final stores = <FileBoardStore>[];
  Future<FileBoardStore> open() async {
    final store = FileBoardStore(directory);
    stores.add(store);
    await store.initialize();
    return store;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'blanko-image-lifecycle-',
    );
  });
  tearDown(() async {
    for (final store in stores.reversed) {
      await store.close();
    }
    stores.clear();
    await directory.delete(recursive: true);
  });

  testWidgets('original PNG and image state survive fresh store reopening', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await _png();
      final session = _session(bytes);
      final store = await open();
      await store.writeAsset('shared-png', bytes);
      final initial = _snapshot(session.document, 1);
      await store.writeBoard(initial, expectedVersion: null);
      await store.writeLastBoard('original');
      await store.close();

      final reopened = await open();
      expect(reopened.writable, isTrue);
      final restored = (await reopened.readBoard('original'))!;
      expect(restored.encode(), initial.encode());
      expect(restored.document.schemaVersion, 1);
      expect(await reopened.readLastBoard(), 'original');
      expect(await reopened.readAsset('shared-png'), orderedEquals(bytes));
      final resumed = BoardSession(document: restored.document);
      final id = resumed.document.elements.single.id;
      expect(resumed.delete(id), isTrue);
      await reopened.writeBoard(
        _snapshot(resumed.document, 2),
        expectedVersion: 1,
      );
      expect(resumed.undo(), isTrue);
      await reopened.writeBoard(
        _snapshot(resumed.document, 3),
        expectedVersion: 2,
      );
      expect(resumed.redo(), isTrue);
      await reopened.writeBoard(
        _snapshot(resumed.document, 4),
        expectedVersion: 3,
      );
      await reopened.close();

      final afterDeletion = await open();
      final deleted = (await afterDeletion.readBoard('original'))!;
      expect(deleted.document.elements, isEmpty);
      expect(deleted.document.assets!.single.id, 'shared-png');
      expect(await afterDeletion.readAsset('shared-png'), orderedEquals(bytes));
      expect(deleted.version, 4);
    });
  });

  testWidgets(
    'image and board duplicates retain shared assets after deletion',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = await _png();
        final session = _session(bytes);
        final originalId = session.document.elements.single.id;
        final duplicateId = session.duplicate(originalId);
        expect(duplicateId, isNotNull);
        expect(session.document.elements, hasLength(2));
        expect(session.document.assets, hasLength(1));
        expect(
          session.document.elements.map(
            (element) => (element.content as ImageElementContent).assetId,
          ),
          everyElement('shared-png'),
        );
        final copy = BoardDocument(
          id: 'copy',
          revision: session.document.revision,
          elements: session.document.elements,
          assets: session.document.assets,
          fontReferences: session.document.fontReferences,
        );
        final expectedCopy = _snapshot(copy, 1);
        final store = await open();
        await store.writeAsset('shared-png', bytes);
        await store.writeBoard(
          _snapshot(session.document, 1),
          expectedVersion: null,
        );
        await store.writeBoard(expectedCopy, expectedVersion: null);
        await store.writeLastBoard('copy');
        await store.deleteBoard('original');
        await store.close();

        final reopened = await open();
        expect(await reopened.readBoard('original'), isNull);
        expect(
          (await reopened.readBoard('copy'))!.encode(),
          expectedCopy.encode(),
        );
        expect(await reopened.readAsset('shared-png'), orderedEquals(bytes));
        expect(await reopened.readLastBoard(), 'copy');
        expect((await reopened.listBoards()).single.document.id, 'copy');
        final restoredCopy = BoardSession(
          document: (await reopened.readBoard('copy'))!.document,
        );
        expect(restoredCopy.delete(originalId), isTrue);
        expect(restoredCopy.document.elements.single.id, duplicateId);
        expect(
          (restoredCopy.document.elements.single.content as ImageElementContent)
              .assetId,
          'shared-png',
        );
      });
    },
  );
}
