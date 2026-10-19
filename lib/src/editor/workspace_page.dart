import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'dart:math';

import 'package:flutter/material.dart';

import '../document/document.dart';
import '../document/document_settings.dart';
import '../geometry/geometry.dart';
import '../persistence/board_autosave.dart';
import '../persistence/board_store.dart';
import '../persistence/close_guard.dart';
import '../persistence/open_board_store.dart';
import '../viewport/camera.dart';
import 'board_session.dart';
import 'editor_canvas.dart';
import 'editor_page.dart';

/// Owns the workspace connection and the lifetime of its one open editor.
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, this.store});
  final BoardStore? store;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  BoardStore? _store;
  EditorCanvasController? _canvas;
  BoardAutosave? _save;
  String? _error;
  bool _busy = true;
  bool _viewDirty = false;
  Timer? _viewTimer;
  late final AppLifecycleListener _lifecycle;
  late final UnsavedCloseGuard _closeGuard;

  bool get _dirty =>
      _viewDirty ||
      (_save != null &&
          _save!.state != SaveState.saved &&
          _save!.state != SaveState.readOnly);

  void _setBusy(bool value) {
    _canvas?.inputEnabled = !value;
    setState(() => _busy = value);
  }

  @override
  void initState() {
    super.initState();
    _closeGuard = UnsavedCloseGuard(() => _dirty);
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        return await _flush() ? AppExitResponse.exit : AppExitResponse.cancel;
      },
      onInactive: () {
        if (_save != null) unawaited(_flush());
      },
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = widget.store ?? await openBoardStore();
      _store = store;
      await store.initialize();
      if (!mounted) {
        await store.close();
        return;
      }
      final last = await store.readLastBoard();
      var snapshot = last == null ? null : await store.readBoard(last);
      if (snapshot == null) {
        final boards = await store.listBoards();
        if (!mounted) {
          await store.close();
          return;
        }
        if (boards.isNotEmpty) {
          snapshot = boards.first;
        } else if (store.writable) {
          snapshot = _newSnapshot('Untitled board');
          await store.writeBoard(snapshot, expectedVersion: null);
        } else {
          throw StateError(
            'Another window owns this workspace. Open a board there first, then retry here.',
          );
        }
      }
      if (!mounted) {
        await store.close();
        return;
      }
      if (store.writable) await store.writeLastBoard(snapshot.document.id);
      if (!mounted) {
        await store.close();
        return;
      }
      _install(snapshot);
    } catch (error) {
      String? cleanupError;
      try {
        await _store?.close();
      } catch (failure) {
        cleanupError = '$failure';
      }
      if (mounted) {
        setState(
          () => _error =
              'Could not open local boards: $error${cleanupError == null ? '' : '\nCould not close storage: $cleanupError'}',
        );
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  BoardSnapshot _newSnapshot(String title) {
    final id =
        'board-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
    final now = DateTime.now().toUtc();
    return BoardSnapshot(
      document: BoardDocument(
        id: id,
        title: title,
        revision: 0,
        elements: [],
        assets: [],
        fontReferences: [],
        canvasSettings: CanvasSettings(
          grid: GridSettings(visible: true, spacing: 40, color: 0xffe9edf3),
        ),
        metadata: DocumentMetadata(createdAt: now, modifiedAt: now),
      ),
      camera: Camera(translation: Point2(80, 80)),
      version: 1,
      savedAt: now,
    );
  }

  void _install(BoardSnapshot snapshot) {
    // Construct before replacing the old session; an unsupported board cannot
    // destroy the current in-memory document or its retry state.
    final next =
        EditorCanvasController(
            session: BoardSession(document: snapshot.document),
            readOnly: !_store!.writable,
          )
          ..camera = snapshot.camera
          ..inputEnabled = !_busy;
    final nextSave = BoardAutosave(store: _store!, initial: snapshot);
    _canvas?.removeListener(_changed);
    _save?.removeListener(_statusChanged);
    _canvas?.dispose();
    _save?.dispose();
    _canvas = next;
    _save = nextSave;
    next.addListener(_changed);
    nextSave.addListener(_statusChanged);
    _viewDirty = false;
    if (mounted) setState(() => _error = null);
  }

  void _statusChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    final canvas = _canvas!, save = _save!;
    if (!canvas.readOnly &&
        !identical(canvas.session.document, save.latest.document)) {
      _viewTimer?.cancel();
      _viewDirty = false;
      save.update(canvas.session.document, canvas.camera);
      return;
    }
    if (canvas.readOnly) return;
    final previous = save.latest.camera, current = canvas.camera;
    if (previous.zoom == current.zoom &&
        previous.translation == current.translation) {
      return;
    }
    if (!_viewDirty) setState(() => _viewDirty = true);
    _viewTimer?.cancel();
    if (!canvas.isNavigating) {
      _viewTimer = Timer(const Duration(milliseconds: 250), _submitView);
    }
  }

  void _submitView() {
    _viewTimer?.cancel();
    if (!_viewDirty || _canvas == null) return;
    _viewDirty = false;
    _save!.update(_canvas!.session.document, _canvas!.camera);
    if (mounted) setState(() {});
  }

  Future<bool> _flush() async {
    _submitView();
    final save = _save;
    if (save == null) return true; // No authored work exists during opening.
    if (_canvas?.readOnly == true) return true;
    return save.flush();
  }

  Future<void> _retry() async {
    _submitView();
    await _save?.retry();
  }

  Future<void> _library() async {
    if (_busy) return;
    _canvas?.cancelGesture();
    _setBusy(true);
    try {
      if (!await _flush()) {
        throw StateError(
          'Current work is still unsaved. Retry saving before switching boards.',
        );
      }
      final boards = await _store!.listBoards();
      if (!mounted) return;
      _setBusy(false);
      final choice = await showDialog<(String, String)>(
        context: context,
        builder: (context) => _BoardLibrary(
          boards: boards,
          writable: _store!.writable,
          location: _store!.location,
        ),
      );
      if (choice == null || !mounted) return;
      _setBusy(true);
      final BoardSnapshot snapshot;
      if (choice.$1 == 'create') {
        snapshot = _newSnapshot(choice.$2);
        await _store!.writeBoard(snapshot, expectedVersion: null);
      } else {
        final record = await _store!.readBoard(choice.$2);
        if (record == null) {
          throw StateError('The board is no longer available.');
        }
        snapshot = record;
      }
      if (!mounted) return;
      if (!await _flush()) {
        throw StateError(
          'Current work is still unsaved. Retry before switching.',
        );
      }
      // Validate rendering support before changing the last-board pointer.
      final candidate = EditorCanvasController(
        session: BoardSession(document: snapshot.document),
      );
      candidate.dispose();
      if (_store!.writable) await _store!.writeLastBoard(snapshot.document.id);
      if (mounted) _install(snapshot);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$error'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _closeGuard.dispose();
    _viewTimer?.cancel();
    _canvas?.removeListener(_changed);
    _save?.removeListener(_statusChanged);
    if (_viewDirty && _canvas != null && !_canvas!.readOnly) {
      _save!.update(_canvas!.session.document, _canvas!.camera);
    }
    final save = _save, store = _store;
    // Normal native exit awaited this drain; widget teardown also retains any
    // accepted queue until the backend is safely closed.
    if (save != null) {
      unawaited(
        save.flush().whenComplete(() async {
          await store?.close();
        }),
      );
      save.dispose();
    }
    _canvas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_canvas == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Whiteboard')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _initialize,
                        child: const Text('Retry opening local boards'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    final save = _save!;
    final status = switch (save.state) {
      SaveState.failed => 'Save failed',
      SaveState.readOnly => 'Read only · another window is editing',
      SaveState.saving => 'Saving…',
      SaveState.saved => _viewDirty ? 'Saving…' : 'Saved locally',
    };
    return Stack(
      children: [
        EditorPage(
          key: ValueKey(_canvas),
          controller: _canvas,
          title: _canvas!.session.document.title,
          actions: [
            IconButton(
              tooltip: 'Boards',
              onPressed: _busy ? null : _library,
              icon: const Icon(Icons.folder_open),
            ),
            if (save.state == SaveState.failed)
              TextButton(onPressed: _retry, child: const Text('Retry save')),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Tooltip(
                  message:
                      save.error ??
                      '${_store!.location} · saved generation ${save.acknowledgedVersion}',
                  child: Text(status, key: const ValueKey('save-status')),
                ),
              ),
            ),
          ],
        ),
        if (save.state == SaveState.failed)
          Positioned(
            left: 12,
            right: 12,
            bottom: 45,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Your work is still open in memory. ${save.error} Retry before closing or switching boards.',
                ),
              ),
            ),
          ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x44000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _BoardLibrary extends StatefulWidget {
  const _BoardLibrary({
    required this.boards,
    required this.writable,
    required this.location,
  });
  final List<BoardSnapshot> boards;
  final bool writable;
  final String location;
  @override
  State<_BoardLibrary> createState() => _BoardLibraryState();
}

class _BoardLibraryState extends State<_BoardLibrary> {
  final _name = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Boards'),
    content: SizedBox(
      width: 460,
      height: 360,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                for (final board in widget.boards)
                  ListTile(
                    title: Text(board.document.title),
                    subtitle: Text(
                      '${board.document.elements.length} elements · revision ${board.document.revision}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.pop(context, ('open', board.document.id)),
                  ),
              ],
            ),
          ),
          if (widget.writable)
            TextField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'New board name',
                hintText: 'Untitled board',
              ),
            ),
          Text(
            widget.location,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (widget.writable)
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            'create',
            _name.text.trim().isEmpty ? 'Untitled board' : _name.text.trim(),
          )),
          child: const Text('Create board'),
        ),
    ],
  );
}
