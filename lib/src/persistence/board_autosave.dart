import 'dart:async';

import 'package:flutter/foundation.dart';

import '../document/document.dart';
import '../viewport/camera.dart';
import 'board_store.dart';

enum SaveState { saved, saving, failed, readOnly }

/// Owns the write queue for one open board; the caller owns its store.
/// Flush before switching boards or closing the store. Undo history is omitted.
final class BoardAutosave extends ChangeNotifier {
  BoardAutosave({required BoardStore store, required BoardSnapshot initial})
    : _store = store,
      _initiallyReadOnly = !store.writable,
      _latest = initial,
      _acknowledgedVersion = initial.version,
      _state = store.writable ? SaveState.saved : SaveState.readOnly;

  final BoardStore _store;
  final bool _initiallyReadOnly;
  BoardSnapshot _latest;
  int _acknowledgedVersion;
  SaveState _state;
  String? _error;
  bool _dirty = false;
  bool _disposed = false;
  Future<void>? _draining;

  BoardSnapshot get latest => _latest;
  int get acknowledgedVersion => _acknowledgedVersion;
  SaveState get state => _state;
  String? get error => _error;

  void update(BoardDocument document, Camera camera) {
    if (_disposed) throw StateError('This board save session is closed.');
    if (document.id != _latest.document.id) {
      throw ArgumentError('An autosave session can only save its own board.');
    }
    if (document.revision < _latest.document.revision) {
      throw ArgumentError(
        'A stale document revision cannot replace newer edits.',
      );
    }
    if (identical(document, _latest.document) &&
        camera.zoom == _latest.camera.zoom &&
        camera.translation == _latest.camera.translation) {
      _hasWriter();
      return;
    }
    _latest = BoardSnapshot(
      document: document,
      camera: camera,
      version: _acknowledgedVersion,
      savedAt: DateTime.now().toUtc(),
    );
    _dirty = true;
    if (_hasWriter() && _state != SaveState.failed) {
      _publish(SaveState.saving);
      _startDrain();
    }
  }

  /// Waits for all accepted edits, including updates arriving during a write.
  /// A failed write requires explicit retry rather than an unbounded retry loop.
  Future<bool> flush() async {
    while (true) {
      if (!_hasWriter()) return false;
      if (_state == SaveState.failed) return false;
      _startDrain();
      final pending = _draining;
      if (pending == null) return !_dirty;
      await pending;
    }
  }

  Future<bool> retry() {
    if (!_hasWriter()) return Future.value(false);
    if (_state == SaveState.failed) {
      _publish(_dirty ? SaveState.saving : SaveState.saved);
      _startDrain();
    }
    return flush();
  }

  void _startDrain() {
    if (_draining != null || !_dirty || !_hasWriter()) return;
    final completion = Completer<void>();
    _draining = completion.future;
    unawaited(_drain(completion));
  }

  Future<void> _drain(Completer<void> completion) async {
    try {
      while (_dirty) {
        if (!_hasWriter()) return;
        final captured = _latest;
        _dirty = false;
        try {
          final snapshot = BoardSnapshot(
            document: captured.document,
            camera: captured.camera,
            version: _acknowledgedVersion + 1,
            savedAt: DateTime.now().toUtc(),
          );
          await _store.writeBoard(
            snapshot,
            expectedVersion: _acknowledgedVersion,
          );
          _acknowledgedVersion = snapshot.version;
          if (identical(_latest, captured)) _latest = snapshot;
        } catch (failure) {
          _dirty = true;
          _publish(
            SaveState.failed,
            'Could not save locally: $failure '
            'Your latest edits remain in memory. Retry before closing.',
          );
          return;
        }
      }
      if (_hasWriter()) _publish(SaveState.saved);
    } finally {
      _draining = null;
      completion.complete();
      // A listener may submit an edit while receiving the saved notification.
      if (_dirty && _state != SaveState.failed) _startDrain();
    }
  }

  bool _hasWriter() {
    if (_initiallyReadOnly) return false;
    if (_store.writable) return true;
    _publish(
      SaveState.failed,
      'Local storage is no longer available for writing. '
      'Your latest edits remain in memory. Restore access and retry before '
      'closing or switching boards.',
    );
    return false;
  }

  void _publish(SaveState state, [String? error]) {
    final changed = _state != state || _error != error;
    _state = state;
    _error = error;
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
