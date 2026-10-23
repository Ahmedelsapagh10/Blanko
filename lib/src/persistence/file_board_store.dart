import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'board_store.dart';

Future<BoardStore> createBoardStore() async {
  const override = String.fromEnvironment('WB_LOCAL_WORKSPACE');
  if (override.isNotEmpty) return FileBoardStore(Directory(override));
  final support = await getApplicationSupportDirectory();
  return FileBoardStore(Directory('${support.path}/boards-v1'));
}

/// One OS-locked workspace. Each acknowledgement follows a flushed atomic rename.
final class FileBoardStore implements BoardStore {
  FileBoardStore(this.directory);

  final Directory directory;
  static final Set<String> _ownedDirectories = {};
  RandomAccessFile? _lock;
  String? _canonicalPath;
  bool _initialized = false;
  bool _closed = false;
  bool _closing = false;
  bool _writable = false;
  int _temporarySequence = 0;
  Future<void> _tail = Future<void>.value();

  @override
  bool get writable => _writable && !_closed;
  @override
  String get location => directory.path;

  @override
  Future<void> initialize() async {
    if (_closed) throw StateError('The local workspace is closed.');
    if (_initialized) return;
    await directory.create(recursive: true);
    final canonical = await directory.resolveSymbolicLinks();
    _canonicalPath = canonical;
    // POSIX advisory locks belong to the process, so also guard same-process
    // handles (e.g. multiple Flutter windows or repository instances).
    if (!_ownedDirectories.add(canonical)) {
      _initialized = true;
      return;
    }
    RandomAccessFile? candidate;
    try {
      candidate = await File(
        '$canonical/.writer.lock',
      ).open(mode: FileMode.append);
      try {
        await candidate.lock(FileLock.exclusive);
      } on FileSystemException catch (error) {
        // POSIX EAGAIN/EACCES and Windows sharing/lock violations signal an
        // existing writer. Opening/permissions/storage failures remain errors.
        if (!{11, 13, 32, 33, 35}.contains(error.osError?.errorCode)) rethrow;
        await candidate.close();
        _ownedDirectories.remove(canonical);
        _initialized = true;
        return;
      }
      _lock = candidate;
      _writable = true;
    } catch (_) {
      await candidate?.close();
      _ownedDirectories.remove(canonical);
      rethrow;
    }
    _initialized = true;
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

  void _checkOpen() {
    if (!_initialized || _closed) {
      throw StateError('The local workspace is not open.');
    }
  }

  void _checkWriter() {
    if (!writable) {
      throw StateError(
        'This workspace is open read-only. Close the other application and reopen it.',
      );
    }
  }

  File _file(String id) {
    final encoded = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
    return File('${directory.path}/$encoded.board.json');
  }

  Future<BoardSnapshot?> _read(String id) async {
    final file = _file(id);
    if (!await file.exists()) return null;
    final snapshot = BoardSnapshot.decode(await file.readAsString());
    if (snapshot.document.id != id) {
      throw const FormatException(
        'Local board identity does not match its filename.',
      );
    }
    return snapshot;
  }

  @override
  Future<BoardSnapshot?> readBoard(String id) => _serial(() => _read(id));

  @override
  Future<List<BoardSnapshot>> listBoards() => _serial(() async {
    final boards = <BoardSnapshot>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.board.json')) continue;
      final snapshot = BoardSnapshot.decode(await entry.readAsString());
      // Directory enumeration uses native separators; constructed paths may use '/'.
      if (_file(snapshot.document.id).uri.pathSegments.last !=
          entry.uri.pathSegments.last) {
        throw const FormatException(
          'Local board identity does not match its filename.',
        );
      }
      boards.add(snapshot);
    }
    boards.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return boards;
  });

  @override
  Future<void> writeBoard(
    BoardSnapshot snapshot, {
    required int? expectedVersion,
  }) => _serial(() async {
    _checkWriter();
    final current = await _read(snapshot.document.id);
    if (current?.version != expectedVersion ||
        snapshot.version != (expectedVersion ?? 0) + 1 ||
        (current != null &&
            snapshot.document.revision < current.document.revision)) {
      throw const StorageConflict();
    }
    await _atomicWrite(_file(snapshot.document.id), snapshot.encode());
  });

  @override
  Future<void> deleteBoard(String id) => _serial(() async {
    _checkWriter();
    final file = _file(id);
    if (await file.exists()) {
      await file.delete();
    }
    final lastFile = File('${directory.path}/last-board.json');
    if (await lastFile.exists()) {
      try {
        final value = jsonDecode(await lastFile.readAsString());
        if (value == id) {
          await lastFile.delete();
        }
      } catch (_) {}
    }
  });

  Future<void> _atomicWrite(File destination, String value) async {
    final temporary = File(
      '${destination.path}.pending-$pid-${_temporarySequence++}',
    );
    try {
      await temporary.writeAsString(value, flush: true);
      // Never delete the acknowledged destination to work around rename errors.
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<String?> readLastBoard() => _serial(() async {
    final file = File('${directory.path}/last-board.json');
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Invalid last-board identity.');
    }
    return value;
  });

  @override
  Future<void> writeLastBoard(String id) => _serial(() async {
    _checkWriter();
    if (await _read(id) == null) {
      throw StateError('Cannot reopen a board that has not been saved.');
    }
    await _atomicWrite(
      File('${directory.path}/last-board.json'),
      jsonEncode(id),
    );
  });

  File _assetFile(String assetId) {
    if (assetId.isEmpty ||
        assetId == '.' ||
        assetId == '..' ||
        assetId.contains('/') ||
        assetId.contains('\\') ||
        assetId.contains('\u0000')) {
      throw ArgumentError.value(
        assetId,
        'assetId',
        'Expected a local asset identifier.',
      );
    }
    return File('${directory.path}/assets/$assetId');
  }

  @override
  Future<Uint8List?> readAsset(String assetId) => _serial(() async {
    final file = _assetFile(assetId);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  });

  @override
  Future<void> writeAsset(String assetId, Uint8List bytes) => _serial(() async {
    _checkWriter();
    final assetsDir = Directory('${directory.path}/assets');
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }
    final file = _assetFile(assetId);
    final temp = File('${file.path}.pending-$pid-${_temporarySequence++}');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  });

  @override
  Future<void> deleteAsset(String assetId) => _serial(() async {
    _checkWriter();
    final file = _assetFile(assetId);
    if (await file.exists()) {
      await file.delete();
    }
  });

  @override
  Future<void> close() async {
    _closing = true;
    await _tail;
    if (_closed) return;
    _closed = true;
    _writable = false;
    final lock = _lock;
    _lock = null;
    if (lock != null) {
      try {
        await lock.unlock();
      } finally {
        await lock.close();
        _ownedDirectories.remove(_canonicalPath);
      }
    }
  }
}
