import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_canvas.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final controller = EditorCanvasController();
  final focusNode = FocusNode(debugLabel: 'Whiteboard canvas');

  @override
  void dispose() {
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
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
      title: const Text('Whiteboard'),
      actions: const [
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
            builder: (context, child) => Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final item in const [
                      (EditorTool.select, Icons.near_me_outlined, 'Select (V)'),
                      (EditorTool.pan, Icons.pan_tool_outlined, 'Pan (H)'),
                      (EditorTool.pen, Icons.edit_outlined, 'Pen (P)'),
                      (
                        EditorTool.rectangle,
                        Icons.rectangle_outlined,
                        'Rectangle (R)',
                      ),
                      (
                        EditorTool.ellipse,
                        Icons.circle_outlined,
                        'Ellipse (O)',
                      ),
                      (
                        EditorTool.triangle,
                        Icons.change_history,
                        'Triangle (T)',
                      ),
                      (EditorTool.line, Icons.horizontal_rule, 'Line (L)'),
                    ])
                      IconButton(
                        tooltip: item.$3,
                        isSelected: controller.tool == item.$1,
                        style: IconButton.styleFrom(
                          backgroundColor: controller.tool == item.$1
                              ? const Color(0xffdbeafe)
                              : null,
                        ),
                        onPressed: () => controller.setTool(item.$1),
                        icon: Icon(item.$2),
                      ),
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
                      tooltip: 'Delete selection',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: controller.selectedId != null
                          ? controller.deleteSelection
                          : null,
                    ),
                    const SizedBox(width: 8),
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
          ),
          Expanded(
            child: EditorCanvas(controller: controller, focusNode: focusNode),
          ),
          ListenableBuilder(
            listenable: controller.toolbarChanges,
            builder: (context, child) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Text(
                controller.message ??
                    (controller.tool == EditorTool.select
                        ? '${controller.elementCount} elements · Select an outline or stroke, then drag · Delete: remove · Esc: cancel'
                        : '${controller.elementCount} elements · Drag to draw · Space / hand: pan · Ctrl/⌘ + scroll: zoom · Esc: cancel'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
