import 'package:flutter/material.dart';

import '../document/element.dart';
import 'editor_canvas.dart';

/// The same actions are exposed by toolbar, mouse menu and touch sheet.
class AdvancedEditorActions extends StatelessWidget {
  const AdvancedEditorActions({super.key, required this.controller});
  final EditorCanvasController controller;

  static List<PopupMenuEntry<String>> entries(EditorCanvasController c) {
    final editable = c.canEditSelection;
    final writable = !c.readOnly && c.inputEnabled && !c.clipboardBusy;
    PopupMenuItem<String> item(String value, String title, bool enabled) {
      final icon = switch (value) {
        'copy' => Icons.copy_outlined,
        'cut' => Icons.content_cut,
        'paste' => Icons.content_paste,
        'delete' => Icons.delete_outline,
        'group' => Icons.workspaces_outline,
        'ungroup' => Icons.grid_view,
        'lock' || 'locked' => Icons.lock_outline,
        'unlock' => Icons.lock_open,
        'front' || 'forward' => Icons.flip_to_front,
        'back' || 'backward' => Icons.flip_to_back,
        'grid' => Icons.grid_4x4,
        'objects' => Icons.align_horizontal_center,
        'multi' => Icons.checklist,
        _ => Icons.tune,
      };
      final shortcut = const {
        'copy': 'Ctrl/Cmd C',
        'cut': 'Ctrl/Cmd X',
        'paste': 'Ctrl/Cmd V',
        'group': 'Ctrl/Cmd G',
        'ungroup': 'Ctrl/Cmd Shift G',
        'duplicate': 'Ctrl/Cmd D',
        'delete': 'Del',
      }[value];
      return PopupMenuItem(
        value: value,
        enabled: enabled,
        child: Builder(
          builder: (context) => Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled && value == 'delete'
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title)),
              if (shortcut != null) ...[
                const SizedBox(width: 12),
                Text(shortcut, style: Theme.of(context).textTheme.labelSmall),
              ],
            ],
          ),
        ),
      );
    }

    return [
      item('all', 'Select all', c.inputEnabled && !c.clipboardBusy),
      item('clear', 'Clear selection', c.hasSelection),
      const PopupMenuDivider(),
      item('copy', 'Copy', c.hasSelection && !c.clipboardBusy),
      item('cut', 'Cut', editable),
      item('paste', 'Paste', writable && c.clipboard.hasContent),
      item('duplicate', 'Duplicate', editable),
      item('delete', 'Delete', editable),
      const PopupMenuDivider(),
      item(
        'group',
        c.selectedIds.length > 1 &&
                c.selectedIds
                        .map((id) => c.session.document.byId[id]!.parentId)
                        .toSet()
                        .length >
                    1
            ? 'Group (same frame or group required)'
            : 'Group',
        editable && c.session.canGroup(c.selectedIds),
      ),
      item(
        'ungroup',
        'Ungroup',
        editable &&
            c.selectedIds.every(
              (id) =>
                  c.session.document.byId[id]?.content is GroupElementContent,
            ),
      ),
      item(
        'enter',
        'Edit group contents',
        c.session.document.byId[c.selectedId]?.content is GroupElementContent,
      ),
      item('exit', 'Exit group', c.editingGroupId != null),
      item('lock', 'Lock selection', editable),
      item(
        'unlock',
        'Unlock selection',
        writable &&
            c.selectedIds.any((id) => c.session.document.byId[id]!.locked),
      ),
      item(
        'locked',
        'Locked items…',
        writable && c.session.document.elements.any((e) => e.locked),
      ),
      const PopupMenuDivider(),
      for (final action in const {
        'front': 'Bring to front',
        'forward': 'Bring forward',
        'backward': 'Send backward',
        'back': 'Send to back',
      }.entries)
        item(action.key, action.value, editable),
      for (final action in const {
        'align-left': 'Align left',
        'hcenter': 'Align horizontal centers',
        'right': 'Align right',
        'top': 'Align top',
        'vcenter': 'Align vertical centers',
        'bottom': 'Align bottom',
        'distribute-h': 'Distribute horizontally',
        'distribute-v': 'Distribute vertically',
      }.entries)
        item(action.key, action.value, c.canLayoutSelection(action.key)),
      const PopupMenuDivider(),
      item(
        'multi',
        '${c.multiSelectMode ? '✓ ' : ''}Touch multi-select',
        writable,
      ),
      item(
        'objects',
        '${c.objectSnapping ? '✓ ' : ''}Snap to objects',
        writable,
      ),
      item('grid', '${c.gridSnapping ? '✓ ' : ''}Snap to grid', writable),
    ];
  }

  static Future<void> perform(
    BuildContext context,
    EditorCanvasController c,
    String action,
  ) async {
    switch (action) {
      case 'all':
        c.selectAll();
      case 'clear':
        c.escapeSelection();
      case 'copy':
        await c.copySelection();
      case 'cut':
        await c.copySelection(cut: true);
      case 'paste':
        await c.pasteSelection();
      case 'duplicate':
        c.duplicateSelection();
      case 'delete':
        c.deleteSelection();
      case 'group':
        c.groupSelection();
      case 'ungroup':
        c.ungroupSelection();
      case 'enter':
        c.enterGroup();
      case 'exit':
        c.exitGroup();
      case 'lock':
        c.lockSelection(true);
      case 'unlock':
        c.lockSelection(false);
      case 'multi':
        c.toggleMultiSelect();
      case 'objects':
        c.toggleSnapping(objects: true);
      case 'grid':
        c.toggleSnapping(objects: false);
      case 'locked':
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Locked items'),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final element in c.session.document.elements.where(
                      (e) => e.locked,
                    ))
                      ListTile(
                        title: Text(element.id.value),
                        subtitle:
                            element.parentId != null &&
                                c.scene.isLocked(element.parentId!)
                            ? const Text('Unlock the parent first')
                            : null,
                        leading: const Icon(Icons.lock_outline),
                        trailing: TextButton(
                          onPressed:
                              element.parentId != null &&
                                  c.scene.isLocked(element.parentId!)
                              ? null
                              : () {
                                  c.unlockElement(element.id);
                                  Navigator.pop(context);
                                },
                          child: const Text('Unlock'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      default:
        if (const ['front', 'forward', 'backward', 'back'].contains(action)) {
          c.reorderSelection(action);
        } else {
          c.layoutSelection(action);
        }
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Selection actions',
    constraints: const BoxConstraints(minWidth: 320, maxWidth: 360),
    icon: const Icon(Icons.more_horiz),
    itemBuilder: (_) => entries(controller),
    onSelected: (value) => perform(context, controller, value),
  );
}
