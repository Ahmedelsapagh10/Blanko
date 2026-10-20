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
import 'editor_text.dart';
import '../theme/blanko_brand.dart';

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
      await ensureEditorFonts();
      if (!mounted) return;
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
          store: _store!,
          currentBoardId: _canvas?.session.document.id,
          onRenameCurrentBoard: (newTitle) async {
            _canvas?.setTitle(newTitle);
            await _flush();
            if (mounted) setState(() {});
          },
        ),
      );
      if (!mounted) return;
      if (choice == null) {
        if (_canvas != null) {
          final exists = await _store!.readBoard(_canvas!.session.document.id);
          if (exists == null) {
            final remaining = await _store!.listBoards();
            _setBusy(true);
            final BoardSnapshot replacement;
            if (remaining.isNotEmpty) {
              replacement = remaining.first;
            } else {
              replacement = _newSnapshot('Untitled board');
              await _store!.writeBoard(replacement, expectedVersion: null);
            }
            if (_store!.writable) {
              await _store!.writeLastBoard(replacement.document.id);
            }
            if (mounted) _install(replacement);
            _setBusy(false);
          }
        }
        return;
      }
      _setBusy(true);
      final BoardSnapshot snapshot;
      if (choice.$1 == 'create') {
        snapshot = _newSnapshot(choice.$2);
        await _store!.writeBoard(snapshot, expectedVersion: null);
      } else if (choice.$1 == 'deleted_current') {
        if (choice.$2.isNotEmpty) {
          final record = await _store!.readBoard(choice.$2);
          snapshot = record ?? _newSnapshot('Untitled board');
          if (record == null) {
            await _store!.writeBoard(snapshot, expectedVersion: null);
          }
        } else {
          snapshot = _newSnapshot('Untitled board');
          await _store!.writeBoard(snapshot, expectedVersion: null);
        }
      } else {
        final record = await _store!.readBoard(choice.$2);
        if (record == null) {
          throw StateError('The board is no longer available.');
        }
        snapshot = record;
      }
      if (!mounted) return;
      if (choice.$1 != 'deleted_current' && !await _flush()) {
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
        body: Center(
          child: _error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BlankoSymbol(size: 64),
                    SizedBox(height: 24),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BlankoSymbol(size: 48),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
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
          leading: const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: BlankoSymbol(size: 24)),
          ),
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
                  child: Text(
                    status,
                    key: const ValueKey('save-status'),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
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
    required this.store,
    required this.currentBoardId,
    this.onRenameCurrentBoard,
  });
  final List<BoardSnapshot> boards;
  final bool writable;
  final String location;
  final BoardStore store;
  final String? currentBoardId;
  final Future<void> Function(String newTitle)? onRenameCurrentBoard;

  @override
  State<_BoardLibrary> createState() => _BoardLibraryState();
}

class _BoardLibraryState extends State<_BoardLibrary> {
  final _name = TextEditingController();
  late final List<BoardSnapshot> _boards = List.of(widget.boards);
  bool _activeBoardDeleted = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _rename(BoardSnapshot board) async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) =>
          _RenameBoardDialog(initialTitle: board.document.title),
    );
    if (newTitle == null || newTitle == board.document.title) return;

    if (board.document.id == widget.currentBoardId &&
        widget.onRenameCurrentBoard != null) {
      await widget.onRenameCurrentBoard!(newTitle);
      final refreshed = await widget.store.readBoard(board.document.id);
      final index =
          _boards.indexWhere((b) => b.document.id == board.document.id);
      if (index >= 0 && refreshed != null) {
        _boards[index] = refreshed;
      }
    } else {
      final updatedDoc = BoardDocument(
        id: board.document.id,
        schemaVersion: board.document.schemaVersion,
        revision: board.document.revision,
        workspaceId: board.document.workspaceId,
        title: newTitle,
        canvasSettings: board.document.canvasSettings,
        assets: board.document.assets,
        fontReferences: board.document.fontReferences,
        metadata: board.document.metadata,
        elements: board.document.elements,
      );
      final updated = BoardSnapshot(
        document: updatedDoc,
        camera: board.camera,
        version: board.version + 1,
        savedAt: DateTime.now().toUtc(),
      );
      await widget.store.writeBoard(updated, expectedVersion: board.version);
      final index =
          _boards.indexWhere((b) => b.document.id == board.document.id);
      if (index >= 0) {
        _boards[index] = updated;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _duplicate(BoardSnapshot board) async {
    final id =
        'board-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
    final title = '${board.document.title} (Copy)';
    final duplicateDoc = BoardDocument(
      id: id,
      schemaVersion: board.document.schemaVersion,
      revision: board.document.revision,
      workspaceId: board.document.workspaceId,
      title: title.length > 120 ? title.substring(0, 120) : title,
      canvasSettings: board.document.canvasSettings,
      assets: board.document.assets,
      fontReferences: board.document.fontReferences,
      metadata: board.document.metadata,
      elements: board.document.elements,
    );
    final duplicate = BoardSnapshot(
      document: duplicateDoc,
      camera: board.camera,
      version: 1,
      savedAt: DateTime.now().toUtc(),
    );
    await widget.store.writeBoard(duplicate, expectedVersion: null);
    _boards.insert(0, duplicate);
    if (mounted) setState(() {});
  }

  Future<void> _delete(BoardSnapshot board) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete board?'),
        content: Text(
          'Are you sure you want to delete "${board.document.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-board'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.deleteBoard(board.document.id);
    _boards.removeWhere((b) => b.document.id == board.document.id);
    if (board.document.id == widget.currentBoardId) {
      _activeBoardDeleted = true;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        BlankoSymbol(size: 24),
        SizedBox(width: 10),
        Text('Blanko Boards', style: TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
    content: SizedBox(
      width: 480,
      height: 380,
      child: Column(
        children: [
          Expanded(
            child: _boards.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BlankoSymbol(size: 40),
                          const SizedBox(height: 16),
                          Text(
                            BlankoBrand.emptyStateHeading,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            BlankoBrand.descriptor,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: BlankoBrand.mutedText),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final board in _boards)
                        ListTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  board.document.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight:
                                        board.document.id ==
                                            widget.currentBoardId
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (board.document.id == widget.currentBoardId)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: BlankoBrand.originBlue.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: BlankoBrand.originBlue,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${board.document.elements.length} elements · revision ${board.document.revision}',
                            style: const TextStyle(
                              color: BlankoBrand.mutedText,
                            ),
                          ),
                          trailing: widget.writable
                              ? PopupMenuButton<String>(
                                  tooltip: 'Board options',
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  onSelected: (action) {
                                    if (action == 'rename') {
                                      unawaited(_rename(board));
                                    } else if (action == 'duplicate') {
                                      unawaited(_duplicate(board));
                                    } else if (action == 'delete') {
                                      unawaited(_delete(board));
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 18),
                                          SizedBox(width: 8),
                                          Text('Rename'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'duplicate',
                                      child: Row(
                                        children: [
                                          Icon(Icons.copy_outlined, size: 18),
                                          SizedBox(width: 8),
                                          Text('Duplicate'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Colors.red,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Delete',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, (
                            'open',
                            board.document.id,
                          )),
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
                hintText: BlankoBrand.defaultBoardTitle,
              ),
            ),
          Text(
            widget.location,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: BlankoBrand.mutedText),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          if (_activeBoardDeleted) {
            Navigator.pop(context, (
              'deleted_current',
              _boards.firstOrNull?.document.id ?? '',
            ));
          } else {
            Navigator.pop(context);
          }
        },
        child: const Text('Close'),
      ),
      if (widget.writable)
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            'create',
            _name.text.trim().isEmpty
                ? BlankoBrand.defaultBoardTitle
                : _name.text.trim(),
          )),
          child: const Text(BlankoBrand.primaryCta),
        ),
    ],
  );
}

class _RenameBoardDialog extends StatefulWidget {
  const _RenameBoardDialog({required this.initialTitle});
  final String initialTitle;

  @override
  State<_RenameBoardDialog> createState() => _RenameBoardDialogState();
}

class _RenameBoardDialogState extends State<_RenameBoardDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    final newTitle = text.isEmpty ? BlankoBrand.defaultBoardTitle : text;
    Navigator.of(context).pop(newTitle);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename board'),
        content: TextField(
          key: const ValueKey('rename-board-input'),
          controller: _controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Board name',
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-rename-board'),
            onPressed: _submit,
            child: const Text('Rename'),
          ),
        ],
      );
}

