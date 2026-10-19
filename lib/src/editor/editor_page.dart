import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/blanko_brand.dart';
import 'editor_canvas.dart';
import 'text_editor_dialog.dart';
import 'editor_text.dart';
import '../document/element.dart';
import '../geometry/geometry.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.controller,
    this.title = BlankoBrand.appName,
    this.leading,
    this.actions = const [],
  });
  final EditorCanvasController? controller;
  final String title;
  final Widget? leading;
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
    }[key];
    if (tool != null) {
      controller.setTool(tool);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading:
          widget.leading ??
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: BlankoSymbol(size: 24)),
          ),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
      ),
      actions: widget.actions.isNotEmpty
          ? widget.actions
          : const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: Text('Session only · not saved')),
              ),
            ],
    ),
    body: Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _key,
      onFocusChange: (focused) {
        if (!focused) controller.focusLost();
      },
      child: Column(
        children: [
          ListenableBuilder(
            listenable: controller.toolbarChanges,
            builder: (context, child) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 4,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final item in const [
                    (EditorTool.select, Icons.near_me_outlined, 'Select (V)'),
                    (EditorTool.pan, Icons.pan_tool_outlined, 'Pan (H)'),
                    (EditorTool.pen, Icons.edit_outlined, 'Pen (P)'),
                    (EditorTool.text, Icons.text_fields, 'Text'),
                    (
                      EditorTool.sticky,
                      Icons.sticky_note_2_outlined,
                      'Sticky note',
                    ),
                    (
                      EditorTool.eraser,
                      Icons.auto_fix_normal,
                      'Object eraser (E)',
                    ),
                    (
                      EditorTool.segmentEraser,
                      Icons.content_cut,
                      'Segment eraser',
                    ),
                    (
                      EditorTool.rectangle,
                      Icons.rectangle_outlined,
                      'Rectangle (R)',
                    ),
                    (EditorTool.ellipse, Icons.circle_outlined, 'Ellipse (O)'),
                    (EditorTool.triangle, Icons.change_history, 'Triangle (T)'),
                    (EditorTool.line, Icons.horizontal_rule, 'Line (L)'),
                  ])
                    IconButton(
                      tooltip: item.$3,
                      isSelected: controller.tool == item.$1,
                      style: IconButton.styleFrom(
                        backgroundColor: controller.tool == item.$1
                            ? BlankoBrand.originBlue.withValues(alpha: 0.12)
                            : null,
                        foregroundColor: controller.tool == item.$1
                            ? BlankoBrand.originBlue
                            : null,
                      ),
                      onPressed: () => controller.setTool(item.$1),
                      icon: Icon(item.$2),
                    ),
                  if (controller.isErasing) ...[
                    Text('Eraser ${controller.eraserSize.round()} px'),
                    SizedBox(
                      width: 120,
                      child: Slider(
                        semanticFormatterCallback: (value) =>
                            '${value.round()} pixels',
                        value: controller.eraserSize,
                        min: 4,
                        max: 120,
                        onChanged: controller.setEraserSize,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  for (final ink in const [
                    0xff202d46,
                    0xff2563eb,
                    0xffdc2626,
                    0xff15803d,
                  ])
                    IconButton(
                      tooltip: switch (ink) {
                        0xff202d46 => 'Ink',
                        0xff2563eb => 'Blue',
                        0xffdc2626 => 'Red',
                        _ => 'Green',
                      },
                      onPressed: () => controller.setColor(ink),
                      icon: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Color(ink),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: controller.color == ink
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  DropdownButton<double>(
                    value: controller.strokeWidth,
                    hint: const Text('Width'),
                    items: const [
                      DropdownMenuItem(value: 2, child: Text('Thin')),
                      DropdownMenuItem(value: 3, child: Text('Medium')),
                      DropdownMenuItem(value: 6, child: Text('Thick')),
                    ],
                    onChanged: (value) {
                      if (value != null) controller.setWidth(value);
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Undo (⌘/Ctrl Z)',
                    icon: const Icon(Icons.undo),
                    onPressed: controller.session.canUndo
                        ? controller.undo
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Redo (⌘/Ctrl Shift Z)',
                    icon: const Icon(Icons.redo),
                    onPressed: controller.session.canRedo
                        ? controller.redo
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Edit text / resize',
                    icon: const Icon(Icons.edit_note),
                    onPressed: controller.selectedId != null
                        ? controller.editSelectedText
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Delete selection',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: controller.selectedId != null
                        ? controller.deleteSelection
                        : null,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Clear All',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed:
                        !controller.readOnly &&
                            controller.inputEnabled &&
                            controller.elementCount > 0
                        ? _clearAll
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Zoom out',
                    icon: const Icon(Icons.remove),
                    onPressed: () => controller.zoom(1 / 1.25),
                  ),
                  Text('${(controller.camera.zoom * 100).round()}%'),
                  IconButton(
                    tooltip: 'Zoom in',
                    icon: const Icon(Icons.add),
                    onPressed: () => controller.zoom(1.25),
                  ),
                  IconButton(
                    tooltip: 'Reset view',
                    icon: const Icon(Icons.home_outlined),
                    onPressed: controller.resetCamera,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: EditorCanvas(controller: controller, focusNode: focusNode),
          ),
          ListenableBuilder(
            listenable: controller.toolbarChanges,
            builder: (context, child) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Text(
                controller.message ??
                    (controller.tool == EditorTool.select
                        ? '${controller.elementCount} elements · Select an outline or stroke, then drag · Delete: remove · Esc: cancel'
                        : '${controller.elementCount} elements · Drag to draw · Space / hand: pan · Ctrl/⌘ + scroll: zoom · Esc: cancel'),
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.75),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
