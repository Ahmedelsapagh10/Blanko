import 'advanced_editor_actions.dart';
import 'drawing_style_dialog.dart';
import 'package:flutter/material.dart';
import 'editor_canvas.dart';
import '../document/element.dart';
import 'image_picker_service.dart' show supportsImagePicking;
import '../theme/blanko_brand.dart';
import 'frame_properties_dialog.dart';

class ToolSurface extends StatelessWidget {
  const ToolSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(6),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Material(
    elevation: 3,
    shadowColor: Colors.black.withValues(alpha: .12),
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BlankoMetrics.panelRadius),
      side: BorderSide(color: Theme.of(context).dividerColor),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class EditorControls extends StatelessWidget {
  const EditorControls({
    super.key,
    required this.controller,
    required this.onClear,
    this.mobile = false,
    this.onHelp,
  });
  final EditorCanvasController controller;
  final VoidCallback onClear;
  final VoidCallback? onHelp;
  final bool mobile;
  static const tools = [
    (EditorTool.select, Icons.near_me_outlined, 'Select (V)'),
    (EditorTool.pan, Icons.pan_tool_outlined, 'Pan (H)'),
    (EditorTool.pen, Icons.edit_outlined, 'Pen (P)'),
    (EditorTool.highlighter, Icons.border_color_outlined, 'Highlighter (M)'),
    (EditorTool.eraser, Icons.cleaning_services_outlined, 'Object eraser (E)'),
    (EditorTool.segmentEraser, Icons.content_cut_outlined, 'Segment eraser'),
    (EditorTool.rectangle, Icons.rectangle_outlined, 'Rectangle (R)'),
    (EditorTool.ellipse, Icons.circle_outlined, 'Ellipse (O)'),
    (EditorTool.triangle, Icons.change_history_outlined, 'Triangle (T)'),
    (EditorTool.line, Icons.horizontal_rule, 'Line (L)'),
    (EditorTool.arrow, Icons.north_east, 'Arrow (A)'),
    (EditorTool.text, Icons.text_fields, 'Text'),
    (EditorTool.sticky, Icons.sticky_note_2_outlined, 'Sticky note'),
    (EditorTool.containerFrame, Icons.crop_portrait_outlined, 'Frame (F)'),
    (EditorTool.exportFrame, Icons.crop_free, 'Export frame'),
  ];
  bool get writable => !controller.readOnly && controller.inputEnabled;
  Widget _tool(BuildContext context, EditorTool tool) {
    final item = tools.firstWhere((item) => item.$1 == tool);
    final selected = controller.tool == tool;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(BlankoMetrics.controlRadius),
      ),
      child: IconButton(
        tooltip: item.$3,
        isSelected: selected,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        onPressed:
            controller.inputEnabled &&
                (writable ||
                    tool == EditorTool.pan ||
                    tool == EditorTool.select)
            ? () => controller.setTool(tool)
            : null,
        icon: Icon(item.$2, size: 22),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    );
  }

  Widget _caption(BuildContext context, Widget button, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      button,
      SizedBox(
        width: 48,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    ],
  );

  Widget _shapes(BuildContext context) => PopupMenuButton<EditorTool>(
    tooltip: 'Shapes',
    popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    icon: Icon(
      Icons.category_outlined,
      color:
          [
            EditorTool.rectangle,
            EditorTool.ellipse,
            EditorTool.triangle,
            EditorTool.line,
            EditorTool.arrow,
          ].contains(controller.tool)
          ? Theme.of(context).colorScheme.primary
          : null,
    ),
    enabled: writable,
    onSelected: controller.setTool,
    itemBuilder: (context) => [
      for (final item in tools.where(
        (t) => [
          EditorTool.rectangle,
          EditorTool.ellipse,
          EditorTool.triangle,
          EditorTool.line,
          EditorTool.arrow,
        ].contains(t.$1),
      ))
        PopupMenuItem(
          value: item.$1,
          child: ListTile(
            dense: true,
            leading: Icon(item.$2),
            title: Text(item.$3),
            selected: controller.tool == item.$1,
          ),
        ),
    ],
  );
  void _more(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tools & board actions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tool in [
                      EditorTool.pan,
                      EditorTool.highlighter,
                      EditorTool.segmentEraser,
                      EditorTool.text,
                      EditorTool.sticky,
                      EditorTool.containerFrame,
                      EditorTool.exportFrame,
                    ])
                      SizedBox(
                        width: 132,
                        child: TextButton.icon(
                          onPressed: writable || tool == EditorTool.pan
                              ? () {
                                  Navigator.pop(context);
                                  controller.setTool(tool);
                                }
                              : null,
                          icon: Icon(tools.firstWhere((t) => t.$1 == tool).$2),
                          label: Text(tools.firstWhere((t) => t.$1 == tool).$3),
                        ),
                      ),
                  ],
                ),
                if (onHelp != null)
                  ListTile(
                    leading: const Icon(Icons.keyboard_outlined),
                    title: const Text('Keyboard & gestures'),
                    onTap: () {
                      Navigator.pop(context);
                      onHelp!();
                    },
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Insert image'),
                  subtitle: supportsImagePicking
                      ? null
                      : const Text('Available on macOS and Web'),
                  enabled: writable && supportsImagePicking,
                  onTap: () {
                    Navigator.pop(context);
                    controller.pickAndInsertImage();
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_sweep_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Clear All'),
                  enabled: writable && controller.elementCount > 0,
                  onTap: () {
                    Navigator.pop(context);
                    onClear();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopMore(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'More tools',
    popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    icon: const Icon(Icons.apps_outlined),
    onSelected: (action) {
      controller.focusLost();
      if (action == 'image') {
        controller.pickAndInsertImage();
      } else if (action == 'clear') {
        onClear();
      } else if (action == 'help') {
        onHelp?.call();
      } else {
        controller.setTool(EditorTool.values.byName(action));
      }
    },
    itemBuilder: (context) => [
      for (final tool in [EditorTool.containerFrame, EditorTool.exportFrame])
        PopupMenuItem(
          value: tool.name,
          enabled: writable,
          child: ListTile(
            dense: true,
            leading: Icon(tools.firstWhere((item) => item.$1 == tool).$2),
            title: Text(tools.firstWhere((item) => item.$1 == tool).$3),
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'image',
        enabled: writable && supportsImagePicking,
        child: const ListTile(
          dense: true,
          leading: Icon(Icons.image_outlined),
          title: Text('Insert image'),
        ),
      ),
      if (onHelp != null)
        const PopupMenuItem(
          value: 'help',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.keyboard_outlined),
            title: Text('Keyboard & gestures'),
          ),
        ),
      PopupMenuItem(
        value: 'clear',
        enabled: writable && controller.elementCount > 0,
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.delete_sweep_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Clear All'),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.toolbarChanges,
    builder: (context, _) {
      if (mobile) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _caption(context, _tool(context, EditorTool.select), 'Select'),
            _caption(context, _tool(context, EditorTool.pen), 'Pen'),
            _caption(context, _tool(context, EditorTool.eraser), 'Eraser'),
            _caption(context, _shapes(context), 'Shapes'),
            _caption(
              context,
              IconButton(
                tooltip: 'More tools',
                onPressed: () => _more(context),
                icon: const Icon(Icons.apps_outlined),
              ),
              'More',
            ),
            _caption(
              context,
              IconButton(
                tooltip: 'Tool properties',
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
                      ? AnimationStyle.noAnimation
                      : null,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (context) => SafeArea(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: EditorProperties(
                          controller: controller,
                          expanded: true,
                        ),
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.tune),
              ),
              'Style',
            ),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tool in [EditorTool.select, EditorTool.pan])
            _tool(context, tool),
          const SizedBox(width: 28, child: Divider()),
          _tool(context, EditorTool.pen),
          _tool(context, EditorTool.highlighter),
          _tool(context, EditorTool.eraser),
          _tool(context, EditorTool.segmentEraser),
          _shapes(context),
          _tool(context, EditorTool.text),
          _tool(context, EditorTool.sticky),
          const SizedBox(width: 28, child: Divider()),
          IconButton(
            tooltip: supportsImagePicking
                ? 'Insert image'
                : 'Image import available on macOS and Web',
            onPressed: writable && supportsImagePicking
                ? controller.pickAndInsertImage
                : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          _desktopMore(context),
        ],
      );
    },
  );
}

class EditorProperties extends StatelessWidget {
  const EditorProperties({
    super.key,
    required this.controller,
    this.expanded = false,
  });
  final EditorCanvasController controller;
  final bool expanded;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.toolbarChanges,
    builder: (context, _) {
      final c = controller, colors = Theme.of(context).colorScheme;
      final writable = !c.readOnly && c.inputEnabled && !c.clipboardBusy;
      final selected = c.session.document.byId[c.selectedId];
      final children = <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            c.selectedIds.length > 1 && c.tool == EditorTool.select
                ? '${c.selectedIds.length} selected'
                : selected != null && c.tool == EditorTool.select
                ? switch (selected.content) {
                    GroupElementContent() => 'Group',
                    ImageElementContent() => 'Image',
                    TextElementContent() => 'Text',
                    StickyNoteElementContent() => 'Sticky note',
                    ContainerFrameElementContent() => 'Frame',
                    ExportFrameElementContent() => 'Export frame',
                    _ => 'Selection',
                  }
                : EditorControls.tools
                      .firstWhere((t) => t.$1 == c.tool)
                      .$3
                      .split(' (')
                      .first,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (c.isErasing) ...[
          if (expanded)
            SegmentedButton<EditorTool>(
              segments: const [
                ButtonSegment(value: EditorTool.eraser, label: Text('Objects')),
                ButtonSegment(
                  value: EditorTool.segmentEraser,
                  label: Text('Segments'),
                ),
              ],
              selected: {c.tool},
              onSelectionChanged: writable
                  ? (value) => c.setTool(value.single)
                  : null,
            ),
          Text('${c.eraserSize.round()} px'),
          SizedBox(
            width: expanded ? 240 : 140,
            child: Slider(
              value: c.eraserSize,
              min: 4,
              max: 120,
              label: '${c.eraserSize.round()} px',
              semanticFormatterCallback: (v) => '${v.round()} pixels',
              onChanged: writable ? c.setEraserSize : null,
            ),
          ),
        ] else if (c.tool == EditorTool.select) ...[
          AdvancedEditorActions(controller: c),
          if (c.selectedDrawing != null)
            IconButton(
              tooltip: 'Drawing style',
              icon: const Icon(Icons.palette_outlined),
              onPressed: c.canStyleSelection
                  ? () => showDrawingStyleDialog(context, c)
                  : null,
            ),
          if (selected?.content is ContainerFrameElementContent ||
              selected?.content is ExportFrameElementContent)
            IconButton(
              tooltip: 'Frame properties',
              onPressed: writable
                  ? () => showFrameProperties(context, c)
                  : null,
              icon: const Icon(Icons.tune),
            ),
          if (selected != null)
            PopupMenuButton<ElementId?>(
              tooltip: 'Place in frame',
              enabled: c.canEditSelection,
              icon: const Icon(Icons.drive_file_move_outline),
              onSelected: c.reparentSelection,
              itemBuilder: (context) => [
                PopupMenuItem<ElementId?>(
                  value: null,
                  onTap: () => c.reparentSelection(null),
                  child: const Text('Move to canvas (detach)'),
                ),
                for (final frame in c.session.document.elements)
                  if (frame.content is ContainerFrameElementContent &&
                      !c.scene.isLocked(frame.id) &&
                      !c.scene.belongsTo(frame.id, selected.id))
                    PopupMenuItem(
                      value: frame.id,
                      child: Text(
                        (frame.content as ContainerFrameElementContent)
                                .label
                                .isEmpty
                            ? 'Frame · ${frame.id.value}'
                            : (frame.content as ContainerFrameElementContent)
                                  .label,
                      ),
                    ),
              ],
            ),
          if (selected?.content is TextElementContent ||
              selected?.content is StickyNoteElementContent)
            IconButton(
              tooltip: 'Edit text / resize',
              onPressed: writable && selected != null
                  ? c.editSelectedText
                  : null,
              icon: const Icon(Icons.edit_note),
            ),
          IconButton(
            tooltip: 'Duplicate (⌘/Ctrl D)',
            onPressed: c.canEditSelection ? c.duplicateSelection : null,
            icon: const Icon(Icons.content_copy_outlined),
          ),
          IconButton(
            tooltip: 'Rotate 90° (⌘/Ctrl R)',
            onPressed: c.canEditSelection ? () => c.rotateSelection() : null,
            icon: const Icon(Icons.rotate_right),
          ),
          IconButton(
            tooltip: 'Delete selection',
            onPressed: c.canEditSelection ? c.deleteSelection : null,
            icon: Icon(
              Icons.delete_outline,
              color: selected != null ? colors.error : null,
            ),
          ),
        ] else if (![
          EditorTool.pan,
          EditorTool.text,
          EditorTool.sticky,
        ].contains(c.tool)) ...[
          IconButton(
            tooltip: 'Drawing style',
            icon: const Icon(Icons.palette_outlined),
            onPressed: writable
                ? () => showDrawingStyleDialog(context, c)
                : null,
          ),
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
              onPressed: writable ? () => c.setColor(ink) : null,
              icon: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Color(ink),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.activeColor == ink
                        ? colors.primary
                        : colors.outline,
                    width: c.activeColor == ink ? 3 : 1,
                  ),
                ),
              ),
            ),
          DropdownButton<double>(
            value: c.activeStrokeWidth,
            underline: const SizedBox(),
            items: [
              for (final w
                  in (c.tool == EditorTool.highlighter
                          ? <double>{12, 24, 40, c.activeStrokeWidth}
                          : <double>{2, 3, 6, c.activeStrokeWidth})
                      .toList()
                    ..sort())
                DropdownMenuItem(
                  value: w,
                  child: Text(
                    c.tool == EditorTool.highlighter
                        ? '${w.round()} px'
                        : switch (w) {
                            2 => 'Thin',
                            3 => 'Medium',
                            6 => 'Thick',
                            _ => '${w.round()} px',
                          },
                  ),
                ),
            ],
            onChanged: writable
                ? (v) {
                    if (v != null) c.setWidth(v);
                  }
                : null,
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              c.tool == EditorTool.pan
                  ? 'Drag to navigate'
                  : 'Tap the canvas to add',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ];
      return Wrap(
        spacing: 4,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    },
  );
}
