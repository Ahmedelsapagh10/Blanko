import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'board_store.dart';

Future<BoardStore> createBoardStore() async => WebBoardStore();

/// Actual IndexedDB transactions, with a lifetime Web Lock for one writer tab.
final class WebBoardStore implements BoardStore {
  WebBoardStore({this.databaseName = 'whiteboard.workspace.v1'});

  final String databaseName;
  web.IDBDatabase? _database;
  Completer<JSAny?>? _releaseLock;
  Future<void>? _lockRequest;
  Future<void> _tail = Future<void>.value();
  bool _writable = false;
  bool _closed = false;
  bool _closing = false;
  bool _invalidated = false;

  @override
  bool get writable => _writable && !_closed && !_invalidated;
  @override
  String get location =>
      'IndexedDB · ${web.window.location.origin} · $databaseName';

  @override
  Future<void> initialize() async {
    if (_closed) throw StateError('The local workspace is closed.');
    if (_database != null) return;
    try {
      final granted = Completer<bool>();
      _releaseLock = Completer<JSAny?>();
      final request = web.window.navigator.locks.request(
        '$databaseName.writer',
        web.LockOptions(mode: 'exclusive', ifAvailable: true),
        ((web.Lock? lock) {
          granted.complete(lock != null);
          return lock == null
              ? Future<JSAny?>.value(null).toJS
              : _releaseLock!.future.toJS;
        }).toJS,
      );
      _lockRequest = request.toDart.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!granted.isCompleted) granted.completeError(error, stack);
          _writable = false;
        },
      );
      _writable = await granted.future;
      _database = await _openDatabase();
      _database!.onversionchange = ((web.Event _) {
        _invalidate();
      }).toJS;
      _database!.onclose = ((web.Event _) {
        _invalidate();
      }).toJS;
    } catch (error) {
      _writable = false;
      _release();
      throw StateError(
        'Browser local storage could not be opened. IndexedDB and Web Locks are required. $error',
      );
    }
  }

  Future<web.IDBDatabase> _openDatabase() {
    final completion = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      database.createObjectStore('boards');
      database.createObjectStore('settings');
    }).toJS;
    request.onsuccess = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      if (completion.isCompleted) {
        database.close();
      } else {
        completion.complete(database);
      }
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.completeError(
          StateError('IndexedDB open failed: ${request.error?.message}'),
        );
      }
    }).toJS;
    request.onblocked = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.completeError(
          StateError(
            'Another browser tab is blocking the local storage upgrade. Close it and retry.',
          ),
        );
      }
    }).toJS;
    return completion.future;
  }

  void _invalidate() {
    _invalidated = true;
    _writable = false;
    _database?.close();
    _release();
  }

  void _release() {
    final release = _releaseLock;
    if (release != null && !release.isCompleted) release.complete(null);
  }

  void _checkOpen() {
    if (_closed || _database == null || _invalidated) {
      throw StateError(
        'The local workspace is closed. Reopen it before continuing.',
      );
    }
  }

  void _checkWriter() {
    if (!writable) {
      throw StateError(
        'This workspace is open read-only. Close the other tab and reopen it.',
      );
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    if (_closing) {
      return Future<T>.error(StateError('The local workspace is closing.'));
    }
    final result = _tail.then((_) async {
      _checkOpen();
      return action();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T> _transaction<T>(
    String storeName, {
    bool write = false,
    required void Function(
      web.IDBObjectStore,
      void Function(T),
      void Function(Object, StackTrace),
    )
    schedule,
  }) {
    _checkOpen();
    if (write) _checkWriter();
    final completion = Completer<T>();
    final transaction = _database!.transaction(
      storeName.toJS,
      write ? 'readwrite' : 'readonly',
      web.IDBTransactionOptions(durability: 'strict'),
    );
    T? result;
    Object? failure;
    StackTrace? failureStack;
    void fail(Object error, StackTrace stack) {
      failure = error;
      failureStack = stack;
      transaction.abort();
    }

    transaction.oncomplete = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.complete(result as T);
      }
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.completeError(
          failure ??
              StateError(
                'Local save transaction aborted: ${transaction.error?.message ?? 'storage unavailable'}',
              ),
          failureStack ?? StackTrace.current,
        );
      }
    }).toJS;
    try {
      schedule(transaction.objectStore(storeName), (value) {
        result = value;
      }, fail);
    } catch (error, stack) {
      fail(error, stack);
    }
    return completion.future;
  }

  @override
  Future<List<BoardSnapshot>> listBoards() => _serial(
    () => _transaction<List<BoardSnapshot>>(
      'boards',
      schedule: (store, done, fail) {
        final request = store.getAll();
        request.onsuccess = ((web.Event _) {
          try {
            final records = (request.result as JSArray<JSString>).toDart;
            final boards = records
                .map((record) => BoardSnapshot.decode(record.toDart))
                .toList();
            boards.sort((a, b) => b.savedAt.compareTo(a.savedAt));
            done(boards);
          } catch (error, stack) {
            fail(error, stack);
          }
        }).toJS;
      },
    ),
  );

  @override
  Future<BoardSnapshot?> readBoard(String id) => _serial(
    () => _transaction<BoardSnapshot?>(
      'boards',
      schedule: (store, done, fail) {
        final request = store.get(id.toJS);
        request.onsuccess = ((web.Event _) {
          try {
            final value = request.result;
            final snapshot = value == null
                ? null
                : BoardSnapshot.decode((value as JSString).toDart);
            if (snapshot != null && snapshot.document.id != id) {
              throw const FormatException('Local board identity mismatch.');
            }
            done(snapshot);
          } catch (error, stack) {
            fail(error, stack);
          }
        }).toJS;
      },
    ),
  );

  @override
  Future<void> writeBoard(
    BoardSnapshot snapshot, {
    required int? expectedVersion,
  }) => _serial(() {
    final encoded = snapshot.encode();
    return _transaction<void>(
      'boards',
      write: true,
      schedule: (store, done, fail) {
        final request = store.get(snapshot.document.id.toJS);
        request.onsuccess = ((web.Event _) {
          try {
            final value = request.result;
            final current = value == null
                ? null
                : BoardSnapshot.decode((value as JSString).toDart);
            if (current != null &&
                current.document.id != snapshot.document.id) {
              throw const FormatException('Local board identity mismatch.');
            }
            if (current?.version != expectedVersion ||
                snapshot.version != (expectedVersion ?? 0) + 1 ||
                (current != null &&
                    snapshot.document.revision < current.document.revision)) {
              throw const StorageConflict();
            }
            // Enqueue inside this request callback: CAS and put share one active
            // transaction. Request success alone is never a save acknowledgement.
            store.put(encoded.toJS, snapshot.document.id.toJS);
          } catch (error, stack) {
            fail(error, stack);
          }
        }).toJS;
      },
    );
  });

  @override
  Future<String?> readLastBoard() => _serial(
    () => _transaction<String?>(
      'settings',
      schedule: (store, done, fail) {
        final request = store.get('last-board'.toJS);
        request.onsuccess = ((web.Event _) {
          try {
            final value = request.result;
            final id = value == null ? null : (value as JSString).toDart;
            if (id != null && id.trim().isEmpty) {
              throw const FormatException('Invalid last-board identity.');
            }
            done(id);
          } catch (error, stack) {
            fail(error, stack);
          }
        }).toJS;
      },
    ),
  );

  @override
  Future<void> writeLastBoard(String id) => _serial(
    () => _transaction<void>(
      'settings',
      write: true,
      schedule: (store, done, fail) {
        if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
        store.put(id.toJS, 'last-board'.toJS);
      },
    ),
  );

  @override
  Future<void> close() async {
    _closing = true;
    await _tail;
    if (_closed) return;
    _closed = true;
    _writable = false;
    _database?.close();
    _release();
    await _lockRequest;
  }
}
