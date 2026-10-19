import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/persistence/file_board_store.dart';
import 'package:whiteboard/src/viewport/camera.dart';

BoardSnapshot snapshot(
  String id,
  int generation,
  int revision, {
  String title = 'Board',
}) => BoardSnapshot(
  document: BoardDocument(
    id: id,
    revision: revision,
    assets: const [],
    fontReferences: const [],
    title: title,
    elements: [
      DocumentElement(
        id: ElementId('shape'),
        revision: revision,
        transform: Transform2.translation(-27.5, 9e6),
        content: ShapeElementContent(
          kind: ShapeKind.ellipse,
          bounds: Bounds2(-10, -5, 70, 35),
          fillColor: 0x55443322,
        ),
      ),
    ],
  ),
  camera: Camera(translation: Point2(18.5, -20), zoom: 1.75),
  version: generation,
  savedAt: DateTime.utc(2026, 10, 19, 10, generation),
);

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
    directory = await Directory.systemTemp.createTemp('whiteboard-store-test-');
  });
  tearDown(() async {
    for (final store in stores.reversed) {
      await store.close();
    }
    stores.clear();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'flushed snapshots and last board survive reopening with exact styles and camera',
    () async {
      final store = await open();
      final original = snapshot('../unsafe/لوحة', 1, 3);
      await store.writeBoard(original, expectedVersion: null);
      await store.writeLastBoard(original.document.id);
      await store.close();
      final reopened = await open();
      expect(reopened.writable, isTrue);
      expect(
        (await reopened.readBoard(original.document.id))!.encode(),
        original.encode(),
      );
      expect(await reopened.readLastBoard(), original.document.id);
      expect((await reopened.listBoards()).single.encode(), original.encode());
    },
  );

  test(
    'rapid queued commits retain latest generation and independent boards',
    () async {
      final store = await open();
      await store.writeBoard(snapshot('a', 1, 1), expectedVersion: null);
      final pending = <Future<void>>[];
      for (var i = 2; i <= 15; i++) {
        pending.add(
          store.writeBoard(snapshot('a', i, i), expectedVersion: i - 1),
        );
      }
      pending.add(
        store.writeBoard(
          snapshot('b', 1, 0, title: 'Second'),
          expectedVersion: null,
        ),
      );
      await Future.wait(pending);
      await store.close();
      final reopened = await open();
      expect((await reopened.readBoard('a'))!.version, 15);
      expect((await reopened.readBoard('b'))!.document.title, 'Second');
      expect(await reopened.listBoards(), hasLength(2));
    },
  );

  test(
    'CAS, stale document revisions and generation skips cannot replace acknowledged data',
    () async {
      final store = await open();
      final original = snapshot('a', 1, 5);
      await store.writeBoard(original, expectedVersion: null);
      await expectLater(
        store.writeBoard(snapshot('a', 2, 6), expectedVersion: null),
        throwsA(isA<StorageConflict>()),
      );
      await expectLater(
        store.writeBoard(snapshot('a', 2, 4), expectedVersion: 1),
        throwsA(isA<StorageConflict>()),
      );
      await expectLater(
        store.writeBoard(snapshot('a', 3, 6), expectedVersion: 1),
        throwsA(isA<StorageConflict>()),
      );
      expect((await store.readBoard('a'))!.encode(), original.encode());
      await store.writeBoard(
        snapshot('a', 2, 5),
        expectedVersion: 1,
      ); // Camera-only save.
    },
  );

  test(
    'second workspace handle is read-only until the writer closes',
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
      final stillReader = await open();
      expect(stillReader.writable, isFalse);
      await writer.close();
      final nextWriter = await open();
      expect(nextWriter.writable, isTrue);
    },
  );

  test(
    'failed atomic rename preserves other acknowledged boards and permits retry',
    () async {
      final store = await open();
      await store.writeBoard(snapshot('safe', 1, 1), expectedVersion: null);
      final encoded = base64Url
          .encode(utf8.encode('blocked'))
          .replaceAll('=', '');
      final obstacle = await Directory(
        '${directory.path}/$encoded.board.json',
      ).create();
      await expectLater(
        store.writeBoard(snapshot('blocked', 1, 0), expectedVersion: null),
        throwsA(isA<FileSystemException>()),
      );
      expect((await store.readBoard('safe'))!.version, 1);
      await obstacle.delete();
      await store.writeBoard(snapshot('blocked', 1, 0), expectedVersion: null);
      expect((await store.readBoard('blocked'))!.version, 1);
      expect(
        await directory
            .list()
            .where((entry) => entry.path.contains('.pending-'))
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'corrupt boards surface errors instead of silently disappearing from library',
    () async {
      final store = await open();
      await store.writeBoard(snapshot('a', 1, 0), expectedVersion: null);
      final encoded = base64Url.encode(utf8.encode('a')).replaceAll('=', '');
      await File(
        '${directory.path}/$encoded.board.json',
      ).writeAsString('{corrupt');
      await expectLater(store.listBoards(), throwsFormatException);
      await expectLater(store.readBoard('a'), throwsFormatException);
      await expectLater(
        store.writeBoard(snapshot('a', 2, 1), expectedVersion: 1),
        throwsFormatException,
      );
    },
  );

  test(
    'OS writer lock rejects a second process, not only another Dart object',
    () async {
      final writer = await open();
      final probe = File('${directory.path}/lock_probe.dart');
      await probe.writeAsString(r'''import 'dart:io';
Future<void> main(List<String> arguments) async {
  final file = await File(arguments.single).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive);
    stdout.write('acquired');
  } on FileSystemException {
    stdout.write('locked');
  } finally { await file.close(); }
}
''');
      final cache = File(
        Platform.resolvedExecutable,
      ).parent.parent.parent.parent;
      final executable =
          '${cache.path}/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
      expect(await File(executable).exists(), isTrue);
      final blocked = await Process.run(executable, [
        probe.path,
        '${directory.path}/.writer.lock',
      ]);
      expect(blocked.exitCode, 0, reason: '${blocked.stderr}');
      expect(blocked.stdout, 'locked');
      await writer.close();
      final released = await Process.run(executable, [
        probe.path,
        '${directory.path}/.writer.lock',
      ]);
      expect(released.exitCode, 0, reason: '${released.stderr}');
      expect(released.stdout, 'acquired');
    },
  );

  test('close drains pending writes and rejects new work', () async {
    final store = await open();
    final pending = store.writeBoard(
      snapshot('a', 1, 0),
      expectedVersion: null,
    );
    final close = store.close();
    await expectLater(
      store.writeBoard(snapshot('b', 1, 0), expectedVersion: null),
      throwsStateError,
    );
    await pending;
    await close;
    final reopened = await open();
    expect(await reopened.readBoard('a'), isNotNull);
    expect(await reopened.readBoard('b'), isNull);
  });
}
