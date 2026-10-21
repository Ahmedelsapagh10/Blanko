import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/blanko_brand.dart';
import 'editor_canvas.dart';
import 'editor_controls.dart';
import '../theme/theme_settings.dart';
import 'text_editor_dialog.dart';
import 'editor_text.dart';
import '../document/element.dart';
import '../geometry/geometry.dart';
import 'png_export_dialog.dart';
import 'project_file_gateway.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.controller,
    this.title = BlankoBrand.appName,
    this.leading,
    this.onRenameBoard,
    this.onSaveProject,
    this.onImportProject,
    this.actions = const [],
  });
  final EditorCanvasController? controller;
  final String title;
  final Widget? leading;
  final VoidCallback? onRenameBoard;
  final VoidCallback? onSaveProject;
  final VoidCallback? onImportProject;
  final List<Widget> actions;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final controller = widget.controller ?? EditorCanvasController();
  final focusNode = FocusNode(debugLabel: 'Blanko canvas');

  @override
  void initState() {
    super.initState();
    controller.onEditText = _editText;
  }

  bool _editingText = false;
  Future<void> _editText(Point2 world, ElementId? id, bool sticky) async {
    if (_editingText || controller.readOnly || !controller.inputEnabled) return;
    _editingText = true;
    controller.focusLost();
    final document = controller.session.document;
    final content = id == null ? null : document.byId[id]?.content;
    try {
      await ensureEditorFonts();
      if (!mounted) return;
      final result = await showBoardTextEditor(
        context,
        content: content,
        sticky:
            content is StickyNoteElementContent || (content == null && sticky),
        color: controller.color,
      );
      if (mounted &&
          identical(document, controller.session.document) &&
          result != null) {
        controller.saveText(result, world, id: id);
      }
    } finally {
      _editingText = false;
      if (mounted) focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    controller.onEditText = null;
    focusNode.dispose();
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  bool _confirmingClear = false;
  Future<void> _clearAll() async {
    if (_confirmingClear ||
        controller.readOnly ||
        !controller.inputEnabled ||
        controller.elementCount == 0) {
      return;
    }
    _confirmingClear = true;
    controller.focusLost();
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => AlertDialog(
        title: const Text('Clear this board?'),
        content: const Text(
          'This will remove all elements from the current board. You can undo this action during the current session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    _confirmingClear = false;
    if (mounted && confirmed == true) controller.clearAll();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!controller.inputEnabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyUpEvent && controller.spaceHeld) {
        controller.spaceHeld = false;
        return KeyEventResult.handled;
      }
      if (!focusNode.hasPrimaryFocus) return KeyEventResult.ignored;
      controller.spaceHeld = event is! KeyUpEvent;
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final command =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.escape) {
      controller.cancelGesture();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyZ) {
      HardwareKeyboard.instance.isShiftPressed
          ? controller.redo()
          : controller.undo();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      controller.redo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      controller.deleteSelection();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyD) {
      controller.duplicateSelection();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyR) {
      controller.rotateSelection();
      return KeyEventResult.handled;
    }
    if (command || HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final tool = {
      LogicalKeyboardKey.keyE: EditorTool.eraser,
      LogicalKeyboardKey.keyV: EditorTool.select,
      LogicalKeyboardKey.keyH: EditorTool.pan,
      LogicalKeyboardKey.keyP: EditorTool.pen,
      LogicalKeyboardKey.keyR: EditorTool.rectangle,
      LogicalKeyboardKey.keyO: EditorTool.ellipse,
      LogicalKeyboardKey.keyT: EditorTool.triangle,
      LogicalKeyboardKey.keyL: EditorTool.line,
      LogicalKeyboardKey.keyF: EditorTool.containerFrame,
    }[key];
    if (tool != null) {
      controller.setTool(tool);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _shortcuts() => showDialog<void>(
    context: context,
    animationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (context) => AlertDialog(
      title: const Text('Keyboard & gestures'),
      content: const SingleChildScrollView(
        child: Text(
          'V  Select     P  Pen     E  Object eraser\nR  Rectangle     O  Ellipse     T  Triangle\nL  Line     H / hold Space  Pan\n\n⌘ / Ctrl + Z  Undo\n⌘ / Ctrl + Shift + Z  Redo\n⌘ / Ctrl + D  Duplicate selection\n⌘ / Ctrl + R  Rotate selection\nDelete  Remove selection     Esc  Cancel\n\nScroll / trackpad  Navigate\n⌘ / Ctrl + scroll  Zoom\nTouch: one finger draws, two fingers navigate.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Widget _historyButtons() => ListenableBuilder(
    listenable: controller.toolbarChanges,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Undo (⌘/Ctrl Z)',
          icon: const Icon(Icons.undo),
          onPressed:
              !controller.readOnly &&
                  controller.inputEnabled &&
                  controller.session.canUndo
              ? controller.undo
              : null,
        ),
        IconButton(
          tooltip: 'Redo (⌘/Ctrl Shift Z)',
          icon: const Icon(Icons.redo),
          onPressed:
              !controller.readOnly &&
                  controller.inputEnabled &&
                  controller.session.canRedo
              ? controller.redo
              : null,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 700 || constraints.maxHeight < 500;
      final colors = Theme.of(context).colorScheme;
      return Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: _key,
        onFocusChange: (focused) {
          if (!focused) controller.focusLost();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            toolbarHeight: compact ? 56 : 64,
            leadingWidth: 52,
            leading:
                widget.leading ?? const Center(child: BlankoSymbol(size: 28)),
            titleSpacing: 4,
            title: Tooltip(
              message: widget.onRenameBoard == null
                  ? widget.title
                  : 'Rename board',
              child: TextButton(
                key: const ValueKey('rename-board-header'),
                onPressed: widget.onRenameBoard,
                style: TextButton.styleFrom(
                  foregroundColor: colors.onSurface,
                  alignment: AlignmentDirectional.centerStart,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (widget.onRenameBoard != null && !compact) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (!compact) _historyButtons(),
              PopupMenuButton<String>(
                tooltip: 'Files & export',
                enabled: supportsProductFiles && controller.inputEnabled,
                icon: const Icon(Icons.file_download_outlined),
                onSelected: (action) {
                  controller.focusLost();
                  if (action == 'png') {
                    showPngExportDialog(context, controller);
                  } else if (action == 'save') {
                    widget.onSaveProject?.call();
                  } else {
                    widget.onImportProject?.call();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'png', child: Text('Export PNG')),
                  if (widget.onSaveProject != null)
                    const PopupMenuItem(
                      value: 'save',
                      child: Text('Save As .wboard'),
                    ),
                  if (widget.onImportProject != null)
                    const PopupMenuItem(
                      value: 'import',
                      child: Text('Import .wboard'),
                    ),
                ],
              ),
              ...widget.actions,
              const ThemeSettingsButton(),
              if (!compact) ...[
                ListenableBuilder(
                  listenable: controller.toolbarChanges,
                  builder: (context, _) => IconButton(
                    tooltip: 'Clear All',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed:
                        !controller.readOnly &&
                            controller.inputEnabled &&
                            controller.elementCount > 0
                        ? _clearAll
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Keyboard shortcuts',
                  onPressed: _shortcuts,
                  icon: const Icon(Icons.keyboard_outlined),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
          bottomNavigationBar: compact
              ? SafeArea(
                  top: false,
                  child: Material(
                    color: colors.surfaceContainerLowest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: EditorControls(
                        controller: controller,
                        onClear: _clearAll,
                        onHelp: _shortcuts,
                        mobile: true,
                      ),
                    ),
                  ),
                )
              : null,
          body: Stack(
            children: [
              Positioned.fill(
                child: EditorCanvas(
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
              if (!compact) ...[
                Positioned(
                  left: 16,
                  top: 16,
                  bottom: 64,
                  width: 60,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      child: ToolSurface(
                        child: EditorControls(
                          controller: controller,
                          onClear: _clearAll,
                          onHelp: _shortcuts,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 92,
                  right: 24,
                  top: 16,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ToolSurface(
                      child: EditorProperties(controller: controller),
                    ),
                  ),
                ),
              ],
              if (compact)
                Positioned(
                  top: 12,
                  left: 12,
                  child: ToolSurface(
                    padding: const EdgeInsets.all(2),
                    child: _historyButtons(),
                  ),
                ),
              Positioned(
                right: compact ? 12 : 20,
                bottom: 16,
                child: ToolSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: ListenableBuilder(
                    listenable: controller.toolbarChanges,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Zoom out',
                          icon: const Icon(Icons.remove, size: 20),
                          onPressed: () => controller.zoom(1 / 1.25),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${(controller.camera.zoom * 100).round()}%',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Zoom in',
                          icon: const Icon(Icons.add, size: 20),
                          onPressed: () => controller.zoom(1.25),
                        ),
                        IconButton(
                          tooltip: 'Reset view',
                          icon: const Icon(
                            Icons.center_focus_strong_outlined,
                            size: 20,
                          ),
                          onPressed: controller.resetCamera,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: compact ? 12 : 92,
                right: compact ? 12 : 300,
                bottom: compact ? 80 : 24,
                child: ListenableBuilder(
                  listenable: controller.toolbarChanges,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (controller.imageCache.errors.isNotEmpty)
                        TextButton(
                          onPressed: controller.retryImages,
                          child: const Text('Retry images'),
                        ),
                      Text(
                        controller.message ??
                            '${controller.elementCount} elements',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          backgroundColor: colors.surfaceContainerLowest,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
