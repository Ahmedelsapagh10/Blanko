import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_autosave.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/viewport/camera.dart';

BoardDocument document(int revision, {String id = 'board'}) => BoardDocument(
  id: id,
  revision: revision,
  elements: [],
  assets: [],
  fontReferences: [],
);

BoardSnapshot initial({BoardDocument? board}) => BoardSnapshot(
  document: board ?? document(0),
  camera: Camera(),
  version: 7,
  savedAt: DateTime.utc(2026, 10, 19),
);

final class _Write {
  _Write(this.snapshot, this.expectedVersion);
  final BoardSnapshot snapshot;
  final int? expectedVersion;
  final completion = Completer<void>();
}

final class _Store implements BoardStore {
  _Store({this.writable = true});
  @override
  bool writable;
  @override
  String get location => 'controlled test store';
  final writes = <_Write>[];
  final committed = <BoardSnapshot>[];
  int active = 0;
  int maximumActive = 0;

  @override
  Future<void> writeBoard(
    BoardSnapshot snapshot, {
    required int? expectedVersion,
  }) async {
    final write = _Write(snapshot, expectedVersion);
    writes.add(write);
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      await write.completion.future;
      committed.add(snapshot);
    } finally {
      active--;
    }
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<List<BoardSnapshot>> listBoards() async => committed;
  @override
  Future<BoardSnapshot?> readBoard(String id) async =>
      committed.where((entry) => entry.document.id == id).lastOrNull;
  @override
  Future<String?> readLastBoard() async => null;
  @override
  Future<void> writeLastBoard(String id) async {}
  @override
  Future<void> close() async {}
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('unchanged document and equivalent viewport do not write', () async {
    final store = _Store();
    final loaded = initial();
    final save = BoardAutosave(store: store, initial: loaded);
    addTearDown(save.dispose);
    expect(save.state, SaveState.saved);
    expect(save.acknowledgedVersion, 7);
    save.update(loaded.document, Camera());
    expect(store.writes, isEmpty);
    expect(await save.flush(), isTrue);
  });

  test(
    'rapid edits coalesce, serialize and never acknowledge an older edit',
    () async {
      final store = _Store();
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      final states = <SaveState>[];
      save.addListener(() => states.add(save.state));
      save.update(document(1), Camera());
      save.update(document(2), Camera());
      final newest = document(3);
      final viewport = Camera(translation: Point2(72, -8), zoom: 2);
      save.update(newest, viewport);
      expect(store.writes, hasLength(1));
      expect(save.state, SaveState.saving);
      final flush = save.flush();
      var flushed = false;
      unawaited(flush.then((_) => flushed = true));
      store.writes.first.completion.complete();
      await settle();
      expect(flushed, isFalse);
      expect(save.state, SaveState.saving);
      expect(save.acknowledgedVersion, 8);
      expect(store.writes, hasLength(2));
      expect(store.writes.last.snapshot.document, same(newest));
      expect(store.writes.last.snapshot.camera, same(viewport));
      expect(store.writes.map((write) => write.expectedVersion), [7, 8]);
      expect(store.writes.map((write) => write.snapshot.version), [8, 9]);
      store.writes.last.completion.complete();
      expect(await flush, isTrue);
      expect(save.state, SaveState.saved);
      expect(save.latest.document, same(newest));
      expect(save.latest.version, 9);
      expect(states, [SaveState.saving, SaveState.saved]);
      expect(store.maximumActive, 1);
    },
  );

  test('flush includes an edit accepted while waiting for a save', () async {
    final store = _Store();
    final save = BoardAutosave(store: store, initial: initial());
    addTearDown(save.dispose);
    save.update(document(1), Camera());
    final flush = save.flush();
    save.update(document(2), Camera());
    store.writes.first.completion.complete();
    await settle();
    expect(store.writes, hasLength(2));
    store.writes.last.completion.complete();
    expect(await flush, isTrue);
    expect(store.committed.last.document.revision, 2);
  });

  test(
    'failed write retains latest edits and explicit retry uses same generation',
    () async {
      final store = _Store();
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      save.update(document(1), Camera());
      final failedFlush = save.flush();
      store.writes.first.completion.completeError(StateError('Disk full'));
      expect(await failedFlush, isFalse);
      expect(save.state, SaveState.failed);
      expect(save.error, contains('Disk full'));
      expect(save.error, contains('remain in memory'));
      expect(save.acknowledgedVersion, 7);
      final newest = document(2);
      save.update(newest, Camera(zoom: 3));
      await settle();
      expect(store.writes, hasLength(1));
      expect(await save.flush(), isFalse);
      final retried = save.retry();
      expect(save.state, SaveState.saving);
      expect(save.error, isNull);
      expect(store.writes.last.snapshot.document, same(newest));
      expect(store.writes.last.snapshot.version, 8);
      expect(store.writes.last.expectedVersion, 7);
      store.writes.last.completion.complete();
      expect(await retried, isTrue);
      expect(save.state, SaveState.saved);
      expect(save.acknowledgedVersion, 8);
    },
  );

  test(
    'storage conflict cannot acknowledge or overwrite a newer stored version',
    () async {
      final store = _Store();
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      save.update(document(1), Camera());
      final flush = save.flush();
      store.writes.single.completion.completeError(const StorageConflict());
      expect(await flush, isFalse);
      expect(save.error, contains('another session'));
      expect(save.latest.document.revision, 1);
      expect(store.committed, isEmpty);
      expect(save.acknowledgedVersion, 7);
    },
  );

  test('undo is saved as a new document and storage revision', () async {
    final store = _Store();
    final loaded = initial();
    final save = BoardAutosave(store: store, initial: loaded);
    addTearDown(save.dispose);
    final session = BoardSession(document: loaded.document);
    session.insert(
      ShapeElementContent(
        kind: ShapeKind.rectangle,
        bounds: Bounds2(0, 0, 10, 20),
        fillColor: 0xff2563eb,
      ),
    );
    save.update(session.document, Camera());
    store.writes.first.completion.complete();
    expect(await save.flush(), isTrue);
    session.undo();
    save.update(session.document, Camera());
    store.writes.last.completion.complete();
    expect(await save.flush(), isTrue);
    expect(store.committed.last.document.elements, isEmpty);
    expect(store.committed.last.document.revision, 2);
    expect(store.committed.last.version, 9);
    expect(
      BoardSession(document: store.committed.last.document).canUndo,
      isFalse,
    );
  });

  test(
    'camera-only changes save without incrementing document revision',
    () async {
      final store = _Store();
      final loaded = initial();
      final save = BoardAutosave(store: store, initial: loaded);
      addTearDown(save.dispose);
      final viewport = Camera(translation: Point2(1e7, -1e7), zoom: .02);
      save.update(loaded.document, viewport);
      expect(save.state, SaveState.saving);
      store.writes.single.completion.complete();
      expect(await save.flush(), isTrue);
      expect(store.committed.single.document, same(loaded.document));
      expect(store.committed.single.camera, same(viewport));
    },
  );

  test(
    'independent board queues do not share content or acknowledgments',
    () async {
      final store = _Store();
      final a = BoardAutosave(store: store, initial: initial());
      final b = BoardAutosave(
        store: store,
        initial: initial(board: document(0, id: 'other')),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.update(document(1), Camera());
      b.update(document(4, id: 'other'), Camera(zoom: 2));
      store.writes.last.completion.complete();
      expect(await b.flush(), isTrue);
      expect(a.state, SaveState.saving);
      expect(a.acknowledgedVersion, 7);
      store.writes.first.completion.complete();
      expect(await a.flush(), isTrue);
      expect(store.committed.map((board) => board.document.id), [
        'other',
        'board',
      ]);
      expect(a.latest.document.id, 'board');
      expect(b.latest.document.id, 'other');
    },
  );

  test(
    'read-only store never writes and retains edits without a saved claim',
    () async {
      final store = _Store(writable: false);
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      final newest = document(1);
      save.update(newest, Camera());
      expect(save.state, SaveState.readOnly);
      expect(save.latest.document, same(newest));
      expect(await save.flush(), isFalse);
      expect(await save.retry(), isFalse);
      expect(store.writes, isEmpty);
    },
  );

  test(
    'writer loss retains edited content as a save failure, not read-only',
    () async {
      final store = _Store();
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      store.writable = false;
      final newest = document(1);
      save.update(newest, Camera(zoom: 2));
      expect(save.state, SaveState.failed);
      expect(save.latest.document, same(newest));
      expect(save.error, contains('no longer available'));
      expect(save.error, contains('remain in memory'));
      expect(await save.flush(), isFalse);
      expect(await save.retry(), isFalse);
      expect(save.state, SaveState.failed);
      expect(save.acknowledgedVersion, 7);
      expect(store.writes, isEmpty);
      store.writable = true;
      final retried = save.retry();
      expect(store.writes.single.snapshot.document, same(newest));
      store.writes.single.completion.complete();
      expect(await retried, isTrue);
      expect(save.state, SaveState.saved);
    },
  );

  test(
    'flush and unchanged update detect lost writer after a saved load',
    () async {
      final store = _Store();
      final loaded = initial();
      final save = BoardAutosave(store: store, initial: loaded);
      addTearDown(save.dispose);
      store.writable = false;
      save.update(loaded.document, loaded.camera);
      expect(save.state, SaveState.failed);
      expect(await save.flush(), isFalse);
      expect(await save.retry(), isFalse);
      expect(save.latest, same(loaded));
      expect(store.writes, isEmpty);
      store.writable = true;
      expect(await save.retry(), isTrue);
      expect(save.state, SaveState.saved);
      store.writable = false;
      expect(await save.flush(), isFalse);
      expect(save.state, SaveState.failed);
    },
  );

  test(
    'writer loss during a pending save cannot acknowledge queued edits',
    () async {
      final store = _Store();
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      save.update(document(1), Camera());
      final newest = document(2);
      save.update(newest, Camera());
      final flushing = save.flush();
      store.writable = false;
      store.writes.single.completion.complete();
      expect(await flushing, isFalse);
      expect(save.state, SaveState.failed);
      expect(save.latest.document, same(newest));
      expect(save.acknowledgedVersion, 8);
      expect(store.writes, hasLength(1));
      expect(store.committed.single.document.revision, 1);
    },
  );

  test(
    'an initially read-only session never promotes itself to a writer',
    () async {
      final store = _Store(writable: false);
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      store.writable = true;
      save.update(document(1), Camera());
      expect(await save.flush(), isFalse);
      expect(await save.retry(), isFalse);
      expect(save.state, SaveState.readOnly);
      expect(store.writes, isEmpty);
    },
  );

  test(
    'stale documents and different board identities are rejected atomically',
    () async {
      final store = _Store();
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      save.update(document(2), Camera());
      final newest = save.latest;
      expect(() => save.update(document(1), Camera()), throwsArgumentError);
      expect(
        () => save.update(document(3, id: 'other'), Camera()),
        throwsArgumentError,
      );
      expect(save.latest, same(newest));
      store.writes.single.completion.complete();
      expect(await save.flush(), isTrue);
    },
  );

  test(
    'dispose drains accepted changes without notifying a disposed owner',
    () async {
      final store = _Store();
      final save = BoardAutosave(store: store, initial: initial());
      var notifications = 0;
      save.addListener(() => notifications++);
      save.update(document(1), Camera());
      save.update(document(2), Camera());
      final flushing = save.flush();
      save.dispose();
      store.writes.first.completion.complete();
      await settle();
      expect(store.writes, hasLength(2));
      store.writes.last.completion.complete();
      expect(await flushing, isTrue);
      expect(store.committed.last.document.revision, 2);
      expect(notifications, 1);
      expect(() => save.update(document(3), Camera()), throwsStateError);
    },
  );

  test(
    'an edit accepted from a saved listener also drains before flush returns',
    () async {
      final store = _Store();
      final save = BoardAutosave(store: store, initial: initial());
      addTearDown(save.dispose);
      var submitted = false;
      save.addListener(() {
        if (save.state == SaveState.saved && !submitted) {
          submitted = true;
          save.update(document(2), Camera());
        }
      });
      save.update(document(1), Camera());
      final flush = save.flush();
      store.writes.first.completion.complete();
      await settle();
      expect(save.state, SaveState.saving);
      expect(store.writes, hasLength(2));
      store.writes.last.completion.complete();
      expect(await flush, isTrue);
      expect(save.latest.document.revision, 2);
    },
  );
}
