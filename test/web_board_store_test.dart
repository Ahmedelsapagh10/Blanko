@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/persistence/web_board_store.dart';
import 'package:whiteboard/src/viewport/camera.dart';

BoardSnapshot snapshot(String id, int generation, int revision) =>
    BoardSnapshot(
      document: BoardDocument(
        id: id,
        revision: revision,
        assets: const [],
        fontReferences: const [],
        title: 'لوحة $id',
        elements: [
          DocumentElement(
            id: ElementId('shape'),
            revision: revision,
            transform: Transform2.translation(-400.25, 12345.75),
            content: ShapeElementContent(
              kind: ShapeKind.ellipse,
              bounds: Bounds2(0, 0, 100, 80),
              fillColor: 0x55443322,
            ),
          ),
        ],
      ),
      camera: Camera(translation: Point2(19.5, -700), zoom: 0.42),
      version: generation,
      savedAt: DateTime.utc(2026, 10, 19, 10, generation),
    );

void main() {
  late String databaseName;
  final stores = <WebBoardStore>[];
  Future<WebBoardStore> open() async {
    final store = WebBoardStore(databaseName: databaseName);
    stores.add(store);
    await store.initialize();
    return store;
  }

  setUp(() {
    databaseName = 'whiteboard.test.${DateTime.now().microsecondsSinceEpoch}';
  });
  tearDown(() async {
    for (final store in stores.reversed) {
      await store.close();
    }
    stores.clear();
    final completion = Completer<void>();
    final request = web.window.indexedDB.deleteDatabase(databaseName);
    request.onsuccess = ((web.Event _) {
      completion.complete();
    }).toJS;
    request.onerror = ((web.Event _) {
      completion.completeError(StateError('Test database cleanup failed.'));
    }).toJS;
    await completion.future;
  });

  test(
    'real IndexedDB retains snapshots and last board after all connections close',
    () async {
      final store = await open();
      expect(store.writable, isTrue);
      expect(store.location, contains('IndexedDB'));
      final original = snapshot('first', 1, 7);
      await store.writeBoard(original, expectedVersion: null);
      await store.writeLastBoard('first');
      await store.close();
      final reopened = await open();
      expect(reopened.writable, isTrue);
      expect((await reopened.readBoard('first'))!.encode(), original.encode());
      expect(await reopened.readLastBoard(), 'first');
      expect((await reopened.listBoards()).single.encode(), original.encode());
    },
  );

  test(
    'explicit connection recovery retains data and enforces existing versions',
    () async {
      final store = await open();
      final original = snapshot('recover', 1, 7);
      await store.writeBoard(original, expectedVersion: null);
      await store.writeLastBoard('recover');
      await store.writeAsset('original', Uint8List.fromList([1, 2, 3]));
      await store.initialize(reconnect: true);
      expect(store.writable, isTrue);
      expect((await store.readBoard('recover'))!.encode(), original.encode());
      expect(await store.readLastBoard(), 'recover');
      expect(await store.readAsset('original'), [1, 2, 3]);
      await expectLater(
        store.writeBoard(snapshot('recover', 3, 9), expectedVersion: 2),
        throwsA(isA<StorageConflict>()),
      );
      await store.writeBoard(snapshot('recover', 2, 8), expectedVersion: 1);
      expect((await store.readBoard('recover'))!.version, 2);
    },
  );

  test(
    'rapid real transactions commit latest generation without mixing boards',
    () async {
      final store = await open();
      await store.writeBoard(snapshot('a', 1, 1), expectedVersion: null);
      final writes = <Future<void>>[];
      for (var generation = 2; generation <= 15; generation++) {
        writes.add(
          store.writeBoard(
            snapshot('a', generation, generation),
            expectedVersion: generation - 1,
          ),
        );
      }
      writes.add(store.writeBoard(snapshot('b', 1, 0), expectedVersion: null));
      await Future.wait(writes);
      await store.close();
      final reopened = await open();
      expect((await reopened.readBoard('a'))!.version, 15);
      expect((await reopened.readBoard('b'))!.version, 1);
      expect(await reopened.listBoards(), hasLength(2));
    },
  );

  test(
    'transactional CAS aborts stale saves and keeps acknowledged record',
    () async {
      final store = await open();
      final original = snapshot('a', 1, 6);
      await store.writeBoard(original, expectedVersion: null);
      await expectLater(
        store.writeBoard(snapshot('a', 2, 7), expectedVersion: null),
        throwsA(isA<StorageConflict>()),
      );
      await expectLater(
        store.writeBoard(snapshot('a', 2, 5), expectedVersion: 1),
        throwsA(isA<StorageConflict>()),
      );
      await expectLater(
        store.writeBoard(snapshot('a', 3, 7), expectedVersion: 1),
        throwsA(isA<StorageConflict>()),
      );
      expect((await store.readBoard('a'))!.encode(), original.encode());
      await store.writeBoard(snapshot('a', 2, 6), expectedVersion: 1);
      expect((await store.readBoard('a'))!.version, 2);
    },
  );

  test(
    'actual Web Lock makes second store read-only, then releases on close',
    () async {
      final writer = await open();
      await writer.writeBoard(snapshot('a', 1, 0), expectedVersion: null);
      final reader = await open();
      expect(reader.writable, isFalse);
      expect(await reader.listBoards(), hasLength(1));
      await expectLater(
        reader.writeBoard(snapshot('b', 1, 0), expectedVersion: null),
        throwsStateError,
      );
      await expectLater(reader.writeLastBoard('a'), throwsStateError);
      await reader.close();
      expect(writer.writable, isTrue);
      await writer.close();
      final nextWriter = await open();
      expect(nextWriter.writable, isTrue);
      await nextWriter.writeBoard(snapshot('b', 1, 0), expectedVersion: null);
    },
  );

  test(
    'closing waits for queued transactions and rejects subsequent edits',
    () async {
      final store = await open();
      final write = store.writeBoard(
        snapshot('a', 1, 0),
        expectedVersion: null,
      );
      final close = store.close();
      await expectLater(
        store.writeBoard(snapshot('b', 1, 0), expectedVersion: null),
        throwsStateError,
      );
      await write;
      await close;
      final reopened = await open();
      expect(await reopened.readBoard('a'), isNotNull);
      expect(await reopened.readBoard('b'), isNull);
    },
  );

  test(
    'malformed persisted data is reported without silently dropping boards',
    () async {
      final store = await open();
      await store.writeBoard(snapshot('a', 1, 0), expectedVersion: null);
      final opened = Completer<web.IDBDatabase>();
      final request = web.window.indexedDB.open(databaseName);
      request.onsuccess = ((web.Event _) {
        opened.complete(request.result as web.IDBDatabase);
      }).toJS;
      final raw = await opened.future;
      final completion = Completer<void>();
      final transaction = raw.transaction('boards'.toJS, 'readwrite');
      transaction.oncomplete = ((web.Event _) {
        completion.complete();
      }).toJS;
      transaction.objectStore('boards').put('{corrupt'.toJS, 'a'.toJS);
      await completion.future;
      raw.close();
      await expectLater(store.listBoards(), throwsFormatException);
      await expectLater(store.readBoard('a'), throwsFormatException);
      await expectLater(
        store.writeBoard(snapshot('a', 2, 1), expectedVersion: 1),
        throwsFormatException,
      );
    },
  );

  test(
    'deleteBoard removes board from IndexedDB and clears last-board pointer',
    () async {
      final store = await open();
      await store.writeBoard(snapshot('board-1', 1, 0), expectedVersion: null);
      await store.writeBoard(snapshot('board-2', 1, 0), expectedVersion: null);
      await store.writeLastBoard('board-1');
      expect(await store.readLastBoard(), 'board-1');

      await store.deleteBoard('board-1');
      expect(await store.readBoard('board-1'), isNull);
      expect(await store.readLastBoard(), isNull);
      expect((await store.listBoards()).map((b) => b.document.id), ['board-2']);
    },
  );
  test(
    'inherited assets upgrade preserves version-one boards and active pointer',
    () async {
      final original = snapshot('legacy', 1, 7);
      final opened = Completer<web.IDBDatabase>();
      final request = web.window.indexedDB.open(databaseName, 1);
      request.onupgradeneeded = ((web.Event _) {
        final db = request.result as web.IDBDatabase;
        db.createObjectStore('boards');
        db.createObjectStore('settings');
      }).toJS;
      request.onsuccess = ((web.Event _) => opened.complete(
        request.result as web.IDBDatabase,
      )).toJS;
      request.onerror = ((web.Event _) => opened.completeError(
        StateError('Fixture open failed'),
      )).toJS;
      final legacy = await opened.future;
      final completed = Completer<void>();
      final tx = legacy.transaction(
        ['boards'.toJS, 'settings'.toJS].toJS,
        'readwrite',
      );
      tx.oncomplete = ((web.Event _) => completed.complete()).toJS;
      tx.onerror = ((web.Event _) => completed.completeError(
        StateError('Fixture write failed'),
      )).toJS;
      tx.objectStore('boards').put(original.encode().toJS, 'legacy'.toJS);
      tx.objectStore('settings').put('legacy'.toJS, 'last-board'.toJS);
      await completed.future;
      legacy.close();
      final store = await open();
      expect((await store.readBoard('legacy'))!.encode(), original.encode());
      expect(await store.readLastBoard(), 'legacy');
      final bytes = Uint8List.fromList([7, 8, 9]);
      await store.writeAsset('sample', bytes);
      await store.close();
      final reopened = await open();
      expect(await reopened.readAsset('sample'), orderedEquals(bytes));
      await reopened.deleteAsset('sample');
      expect(await reopened.readAsset('sample'), isNull);
    },
  );
}
