import 'dart:async';
import 'dart:typed_data';

import 'package:whiteboard/src/persistence/board_store.dart';

/// Explicit test double only. Production always opens file storage or IndexedDB.
class TestBoardStore implements BoardStore {
  final records = <String, String>{};
  final assets = <String, Uint8List>{};
  String? last;
  bool failWrites = false, failInitialize = false, failLast = false;
  bool closed = false;
  bool failClose = false;
  bool readOnly = false;
  int writes = 0;
  Completer<void>? writeGate;
  Completer<void>? initializeGate;
  @override
  bool get writable => !readOnly;
  @override
  String get location => 'Injected test store';
  @override
  Future<void> initialize() async {
    if (initializeGate != null) await initializeGate!.future;
    if (failInitialize) throw StateError('Storage unavailable');
    closed = false;
  }

  @override
  Future<List<BoardSnapshot>> listBoards() async =>
      records.values.map(BoardSnapshot.decode).toList();
  @override
  Future<BoardSnapshot?> readBoard(String id) async =>
      records[id] == null ? null : BoardSnapshot.decode(records[id]!);
  @override
  Future<String?> readLastBoard() async => last;
  @override
  Future<void> writeLastBoard(String id) async {
    if (failLast) throw StateError('Settings write denied');
    if (!writable) throw StateError('Read only');
    last = id;
  }

  @override
  Future<void> writeBoard(
    BoardSnapshot snapshot, {
    required int? expectedVersion,
  }) async {
    final gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    if (failWrites) throw StateError('Disk quota exceeded');
    if (!writable) throw StateError('Read only');
    final previous = await readBoard(snapshot.document.id);
    if (previous?.version != expectedVersion) throw const StorageConflict();
    records[snapshot.document.id] = snapshot.encode();
    writes++;
  }

  @override
  Future<void> deleteBoard(String id) async {
    if (!writable) throw StateError('Read only');
    records.remove(id);
    if (last == id) last = null;
  }

  @override
  Future<Uint8List?> readAsset(String assetId) async => assets[assetId];

  @override
  Future<void> writeAsset(String assetId, Uint8List bytes) async {
    if (!writable) throw StateError('Read only');
    assets[assetId] = bytes;
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    if (!writable) throw StateError('Read only');
    assets.remove(assetId);
  }

  @override
  Future<void> close() async {
    if (failClose) throw StateError('Close denied');
    closed = true;
  }
}
