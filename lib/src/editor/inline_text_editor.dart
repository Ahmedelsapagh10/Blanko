// Pinned Quill 11.5 clipboard/key APIs are covered by integration tests.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;

import '../document/element.dart';
import '../geometry/geometry.dart';
import 'color_picker_widget.dart';
import 'editor_canvas.dart';
import 'editor_controls.dart';
import 'editor_text.dart';

/// Quill 11.5 maps left/right to start/end. Keep persistent alignment physical
/// and translate only at the widget boundary. Applying twice is the inverse.
List<Map<String, Object?>> quillEditingDelta(
  List<Map<String, Object?>> delta,
) => [
  for (final op in delta)
    if (op['attributes'] case final Map attributes
        when attributes['direction'] == 'rtl' &&
            (attributes['align'] == 'left' || attributes['align'] == 'right'))
      {
        ...op,
        'attributes': {
          ...attributes,
          'align': attributes['align'] == 'left' ? 'right' : 'left',
        },
      }
    else
      Map<String, Object?>.from(op),
];

List<Map<String, Object?>> _legacyDelta(ElementContent content, String text) {
  final (direction, alignment) = switch (content) {
    TextElementContent(:final direction, :final alignment) ||
    StickyNoteElementContent(
      :final direction,
      :final alignment,
    ) => (direction, alignment),
    _ => throw ArgumentError('Expected text'),
  };
  return [
    for (final line in text.split('\n')) ...[
      if (line.isNotEmpty) {'insert': line},
      {
        'insert': '\n',
        'attributes': {
          if (line.isNotEmpty || direction != ElementTextDirection.auto)
            'direction':
                elementTextDirection(line, direction) == TextDirection.rtl
                ? 'rtl'
                : 'ltr',
          if (alignment != ElementTextAlignment.start)
            'align': switch (alignment) {
              ElementTextAlignment.end =>
                elementTextDirection(line, direction) == TextDirection.rtl
                    ? 'left'
                    : 'right',
              _ => alignment.name,
            },
        },
      },
    ],
  ];
}

/// One object owns the live editor. Only debounced immutable checkpoints enter
/// the document; BoardSession keeps one inverse for the complete transaction.
class InlineTextDraft extends ChangeNotifier {
  InlineTextDraft({
    required this.original,
    required this.onDirty,
    required this.onCheckpoint,
    required this.onUnchanged,
    required this.onFinish,
  }) {
    final rich = switch (original) {
      TextElementContent() => (original as TextElementContent).richText,
      StickyNoteElementContent() =>
        (original as StickyNoteElementContent).richText,
      _ => throw ArgumentError('Expected text'),
    };
    final text = switch (original) {
      TextElementContent() => (original as TextElementContent).text,
      StickyNoteElementContent() => (original as StickyNoteElementContent).text,
      _ => '',
    };
    final delta = quillEditingDelta(
      rich?.delta ?? _legacyDelta(original, text),
    );
    editor = q.QuillController(
      document: q.Document.fromJson(jsonDecode(jsonEncode(delta)) as List),
      selection: TextSelection.collapsed(offset: text.length),
      onReplaceText: (index, length, data) {
        if (data is! String) return false;
        final nextLength = editor.document.length - length + data.length;
        if (nextLength > 200000 && nextLength > editor.document.length) {
          error = 'Text is limited to 200,000 characters.';
          notifyListeners();
          return false;
        }
        return true;
      },
      config: q.QuillControllerConfig(
        clipboardConfig: q.QuillClipboardConfig(
          enableExternalRichPaste: false,
          onClipboardPaste: _paste,
        ),
      ),
    );
    _initialDelta = jsonEncode(editor.document.toDelta().toJson());
    _lastCheckpoint = _initialDelta;
    editor.addListener(_changed);
  }

  final ElementContent original;
  final VoidCallback onDirty;
  final ValueChanged<ElementContent> onCheckpoint;
  final VoidCallback onUnchanged;
  final ValueChanged<bool> onFinish;
  late final q.QuillController editor;
  final focus = FocusNode(debugLabel: 'Blanko inline text');
  final scroll = ScrollController();
  final rawKey = GlobalKey<q.EditorState>();
  late final String _initialDelta;
  late String _lastCheckpoint;
  Timer? _timer;
  int _generation = 0;
  bool _closed = false;
  bool _normalizing = false;
  int _toolbarRoutes = 0;
  String? error;

  ElementTextStyle get style => switch (original) {
    TextElementContent(:final style) ||
    StickyNoteElementContent(:final style) => style,
    _ => throw StateError('Expected text'),
  };
  Bounds2 get bounds => switch (original) {
    TextElementContent(:final bounds) ||
    StickyNoteElementContent(:final bounds) => bounds,
    _ => throw StateError('Expected text'),
  };
  bool get composing {
    final raw = rawKey.currentState;
    return raw is q.QuillRawEditorState &&
        raw.composingRange.value.isValid &&
        !raw.composingRange.value.isCollapsed;
  }

  void _changed() {
    if (_closed || _normalizing) return;
    final value = jsonEncode(editor.document.toDelta().toJson());
    if (value != _lastCheckpoint) {
      _generation++;
      onDirty();
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 350), checkpoint);
    }
    notifyListeners();
  }

  Future<bool> _paste() async {
    final generation = _generation, selection = editor.selection;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (_closed ||
          generation != _generation ||
          selection != editor.selection) {
        return true;
      }
      final text = data?.text?.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      if (text == null) return true;
      if (text.length + editor.document.length > 200000) {
        error = 'Text is limited to 200,000 characters.';
        notifyListeners();
        return true;
      }
      editor.replaceText(
        selection.start,
        selection.end - selection.start,
        text,
        TextSelection.collapsed(offset: selection.start + text.length),
      );
    } catch (_) {
      if (!_closed) {
        error = 'Could not paste. Try the keyboard paste command again.';
        notifyListeners();
      }
    }
    return true;
  }

  /// Direction changes never run against an active platform composing range.
  void _directions() {
    if (composing) return;
    var offset = 0;
    var line = StringBuffer();
    final changes = <(int, bool)>[];
    for (final op in editor.document.toDelta().toJson()) {
      final text = op['insert'] as String;
      final attributes = op['attributes'] as Map?;
      for (var i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) {
          if (attributes?['direction'] == null) {
            final direction = switch (original) {
              TextElementContent(:final direction) ||
              StickyNoteElementContent(:final direction) => direction,
              _ => ElementTextDirection.auto,
            };
            if (elementTextDirection(line.toString(), direction) ==
                TextDirection.rtl) {
              changes.add((offset + i, true));
            }
          }
          line = StringBuffer();
        } else {
          line.writeCharCode(text.codeUnitAt(i));
        }
      }
      offset += text.length;
    }
    _normalizing = true;
    final history = editor.document.history;
    final ignored = history.ignoreChange;
    history.ignoreChange = true;
    try {
      for (final (offset, _) in changes) {
        final change = editor.document.format(offset, 1, q.Attribute.rtl);
        history.transform(change);
      }
      if (changes.isNotEmpty) {
        editor.updateSelection(editor.selection, q.ChangeSource.local);
      }
    } finally {
      history.ignoreChange = ignored;
      _normalizing = false;
    }
  }

  ElementContent _content() {
    final rich = RichTextData.fromJson({
      'version': 1,
      'delta': quillEditingDelta(
        editor.document
            .toDelta()
            .toJson()
            .map((op) => Map<String, Object?>.from(op))
            .toList(),
      ),
    });
    ElementContent make(double height) {
      final box = Bounds2(
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.top + height,
      );
      return switch (original) {
        TextElementContent(:final direction, :final alignment) =>
          TextElementContent(
            text: rich.plainText,
            richText: rich,
            bounds: box,
            style: style,
            direction: direction,
            alignment: alignment,
            sizing: TextSizing.autoHeight,
          ),
        StickyNoteElementContent(
          :final direction,
          :final alignment,
          :final backgroundColor,
        ) =>
          StickyNoteElementContent(
            text: rich.plainText,
            richText: rich,
            bounds: box,
            style: style,
            direction: direction,
            alignment: alignment,
            backgroundColor: backgroundColor,
            sizing: TextSizing.autoHeight,
          ),
        _ => throw StateError('Expected text'),
      };
    }

    final layout = layoutElementText(make(bounds.height));
    try {
      return make(
        math.max(
          original is StickyNoteElementContent ? 120 : style.fontSize * 1.3,
          layout.height + (original is StickyNoteElementContent ? 24 : 0),
        ),
      );
    } finally {
      layout.dispose();
    }
  }

  void checkpoint() {
    if (_closed) return;
    _timer?.cancel();
    try {
      _directions();
      final value = jsonEncode(editor.document.toDelta().toJson());
      if (value == _lastCheckpoint) {
        error = null;
        onUnchanged();
        return;
      }
      onCheckpoint(_content());
      _lastCheckpoint = value;
      error = null;
    } catch (failure) {
      error = 'Text is still in memory: $failure';
      notifyListeners();
    }
  }

  bool finish({bool cancel = false}) {
    if (_closed) return true;
    if (!cancel) {
      checkpoint();
      if (error != null) return false;
    }
    _closed = true;
    _timer?.cancel();
    onFinish(cancel);
    return true;
  }

  void format(q.Attribute attribute) {
    if (_closed || composing) return;
    _directions();
    editor.formatSelection(attribute);
    focus.requestFocus();
  }

  KeyEventResult? handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return null;
    final key = event.logicalKey;
    if (composing && key != LogicalKeyboardKey.space) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      editor.updateSelection(
        TextSelection(baseOffset: 0, extentOffset: editor.document.length - 1),
        q.ChangeSource.local,
      );
    } else if (key == LogicalKeyboardKey.keyV) {
      unawaited(_paste());
    } else if (key == LogicalKeyboardKey.keyC && !keyboard.isShiftPressed) {
      editor.clipboardSelection(true);
    } else if (key == LogicalKeyboardKey.keyX) {
      editor.clipboardSelection(false);
    } else if (key == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed ? editor.redo() : editor.undo();
    } else if (key == LogicalKeyboardKey.keyY) {
      editor.redo();
    } else if (const [
          LogicalKeyboardKey.backquote,
          LogicalKeyboardKey.tilde,
          LogicalKeyboardKey.keyM,
          LogicalKeyboardKey.keyG,
          LogicalKeyboardKey.digit0,
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
        ].contains(key) ||
        keyboard.isShiftPressed &&
            (key == LogicalKeyboardKey.keyB ||
                key == LogicalKeyboardKey.keyC)) {
      // This text-only format deliberately excludes embeds, nested lists,
      // headings and code blocks. Do not let hidden package shortcuts add them.
    } else {
      return null;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    editor.removeListener(_changed);
    editor.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }
}

class InlineTextLayer extends StatefulWidget {
  const InlineTextLayer({
    super.key,
    required this.draft,
    required this.controller,
  });
  final InlineTextDraft draft;
  final EditorCanvasController controller;

  @override
  State<InlineTextLayer> createState() => _InlineTextLayerState();
}

class _InlineTextLayerState extends State<InlineTextLayer> {
  InlineTextDraft get draft => widget.draft;
  EditorCanvasController get controller => widget.controller;
  bool _revealQueued = false;

  @override
  void initState() {
    super.initState();
    draft.addListener(_revealCaret);
    _revealCaret();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.viewInsetsOf(context);
    _revealCaret();
  }

  void _revealCaret() {
    if (_revealQueued) return;
    _revealQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealQueued = false;
      if (!mounted ||
          draft._closed ||
          !draft.focus.hasFocus ||
          controller.isNavigating) {
        return;
      }
      final raw = draft.rawKey.currentState;
      final layer = context.findRenderObject();
      if (raw == null || layer is! RenderBox || !layer.hasSize) return;
      final render = raw.renderEditor;
      if (!render.attached || !render.hasSize) return;
      final caret = render.getLocalRectForCaret(draft.editor.selection.extent);
      final top = layer.globalToLocal(render.localToGlobal(caret.topLeft));
      final bottom = layer.globalToLocal(
        render.localToGlobal(caret.bottomRight),
      );
      final dx = top.dx < 12
          ? 12 - top.dx
          : bottom.dx > layer.size.width - 12
          ? layer.size.width - 12 - bottom.dx
          : 0.0;
      final dy = top.dy < 72
          ? 72 - top.dy
          : bottom.dy > layer.size.height - 20
          ? layer.size.height - 20 - bottom.dy
          : 0.0;
      if (dx.abs() > .5 || dy.abs() > .5) {
        controller.revealTextCaret(Offset(dx, dy));
      }
    });
  }

  @override
  void dispose() {
    draft.removeListener(_revealCaret);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _revealCaret();
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final id = controller.editingTextId;
          if (id == null || !controller.session.document.byId.containsKey(id)) {
            return const SizedBox();
          }
          final transform = controller.scene.worldTransformOf(id);
          final camera = controller.camera;
          final b = draft.bounds;
          final p = camera.worldToViewport(
            transform.apply(Point2(b.left, b.top)),
          );
          final matrix = Matrix4.identity()
            ..setEntry(0, 0, transform.a * camera.zoom)
            ..setEntry(1, 0, transform.b * camera.zoom)
            ..setEntry(0, 1, transform.c * camera.zoom)
            ..setEntry(1, 1, transform.d * camera.zoom)
            ..setEntry(0, 3, p.x)
            ..setEntry(1, 3, p.y);
          final style = baseElementTextStyle(draft.style);
          final block = q.DefaultTextBlockStyle(
            style,
            const q.HorizontalSpacing(0, 0),
            q.VerticalSpacing.zero,
            q.VerticalSpacing.zero,
            null,
          );
          final padding = draft.original is StickyNoteElementContent
              ? 12.0
              : 0.0;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: Transform(
                  transform: matrix,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: b.width,
                    child: TextFieldTapRegion(
                      groupId: draft,
                      onTapOutside: (_) {
                        if (draft._toolbarRoutes == 0) draft.finish();
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: draft.original is StickyNoteElementContent
                              ? Color(
                                  (draft.original as StickyNoteElementContent)
                                      .backgroundColor,
                                )
                              : null,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1 / camera.zoom,
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(padding),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: q.QuillEditor(
                              key: const ValueKey('board-inline-text'),
                              controller: draft.editor,
                              focusNode: draft.focus,
                              scrollController: draft.scroll,
                              config: q.QuillEditorConfig(
                                editorKey: draft.rawKey,
                                autoFocus: true,
                                scrollable: false,
                                padding: EdgeInsets.zero,
                                minHeight:
                                    draft.original is StickyNoteElementContent
                                    ? 120 - padding * 2
                                    : draft.style.fontSize * 1.3,
                                onTapOutsideEnabled: false,
                                onLaunchUrl: (_) {},
                                customStyles: q.DefaultStyles(
                                  link: const TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                  paragraph: block,
                                  leading: block,
                                  align: block,
                                  lists: q.DefaultListBlockStyle(
                                    style,
                                    const q.HorizontalSpacing(0, 0),
                                    q.VerticalSpacing.zero,
                                    q.VerticalSpacing.zero,
                                    null,
                                    null,
                                    indentWidthBuilder: (block, _, _, _) =>
                                        q.HorizontalSpacing(
                                          block.style.containsKey(
                                                q.Attribute.list.key,
                                              )
                                              ? 32
                                              : 0,
                                          0,
                                        ),
                                    numberPointWidthBuilder: (_, _) => 32,
                                  ),
                                ),
                                onKeyPressed: (event, _) {
                                  if (event is! KeyDownEvent) return null;
                                  final handled = draft.handleKey(event);
                                  if (handled != null) return handled;
                                  if ((HardwareKeyboard
                                              .instance
                                              .isControlPressed ||
                                          HardwareKeyboard
                                              .instance
                                              .isMetaPressed) &&
                                      event.logicalKey ==
                                          LogicalKeyboardKey.keyK) {
                                    unawaited(_setLink(context, draft));
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.escape) {
                                    draft.finish(cancel: true);
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.tab) {
                                    return KeyEventResult.handled;
                                  }
                                  if ((HardwareKeyboard
                                              .instance
                                              .isControlPressed ||
                                          HardwareKeyboard
                                              .instance
                                              .isMetaPressed) &&
                                      event.logicalKey ==
                                          LogicalKeyboardKey.enter) {
                                    draft.finish();
                                    return KeyEventResult.handled;
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: MediaQuery.sizeOf(context).width < 720 ? 8 : 92,
                right: 8,
                top: 8,
                child: TextFieldTapRegion(
                  groupId: draft,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ToolSurface(child: _TextFormatting(draft: draft)),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _TextFormatting extends StatelessWidget {
  const _TextFormatting({required this.draft});
  final InlineTextDraft draft;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      final selected = draft.editor.getSelectionStyle().attributes;
      Widget toggle(String label, IconData icon, q.Attribute attribute) =>
          IconButton(
            tooltip: label,
            visualDensity: VisualDensity.compact,
            isSelected: selected[attribute.key]?.value == attribute.value,
            onPressed: () => draft.format(
              q.Attribute.clone(
                attribute,
                selected[attribute.key]?.value == attribute.value
                    ? null
                    : attribute.value,
              ),
            ),
            icon: Icon(icon, size: 20),
          );
      Widget menu<T>(
        String label,
        IconData icon,
        List<PopupMenuEntry<T>> items,
        FutureOr<void> Function(T) onSelected,
      ) => PopupMenuButton<T>(
        tooltip: label,
        icon: Icon(icon, size: 20),
        onOpened: () => draft._toolbarRoutes++,
        onCanceled: () => draft._toolbarRoutes--,
        onSelected: (value) async {
          try {
            await onSelected(value);
          } finally {
            draft._toolbarRoutes--;
          }
        },
        itemBuilder: (_) => items,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                toggle('Bold', Icons.format_bold, q.Attribute.bold),
                toggle('Italic', Icons.format_italic, q.Attribute.italic),
                toggle(
                  'Underline',
                  Icons.format_underlined,
                  q.Attribute.underline,
                ),
                toggle(
                  'Strikethrough',
                  Icons.format_strikethrough,
                  q.Attribute.strikeThrough,
                ),
                menu<String>(
                  'Font family',
                  Icons.font_download_outlined,
                  [
                    for (final font in ['Roboto', 'Noto Sans Arabic'])
                      PopupMenuItem(value: font, child: Text(font)),
                  ],
                  (v) => draft.format(q.FontAttribute(v)),
                ),
                menu<String>(
                  'Font size',
                  Icons.format_size,
                  [
                    for (final size in [
                      8,
                      12,
                      16,
                      20,
                      24,
                      32,
                      36,
                      48,
                      64,
                      96,
                      144,
                    ])
                      PopupMenuItem(value: '$size', child: Text('$size')),
                  ],
                  (v) => draft.format(q.SizeAttribute(v)),
                ),
                menu<String>(
                  'Text color',
                  Icons.format_color_text,
                  [
                    for (final color in ColorPickerWidget.defaultPalette)
                      PopupMenuItem(
                        value:
                            '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                        child: Row(
                          children: [
                            Icon(Icons.circle, color: Color(color)),
                            const SizedBox(width: 12),
                            Text(
                              '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                            ),
                          ],
                        ),
                      ),
                  ],
                  (v) => draft.format(q.ColorAttribute(v)),
                ),
                menu<String>(
                  'Text highlight',
                  Icons.format_color_fill,
                  [
                    const PopupMenuItem(value: '', child: Text('No highlight')),
                    for (final color in ColorPickerWidget.highlighterPalette)
                      PopupMenuItem(
                        value:
                            '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                        child: Row(
                          children: [
                            Icon(Icons.circle, color: Color(color)),
                            const SizedBox(width: 12),
                            Text(
                              '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                            ),
                          ],
                        ),
                      ),
                  ],
                  (v) =>
                      draft.format(q.BackgroundAttribute(v.isEmpty ? null : v)),
                ),
                menu<String>(
                  'Paragraph alignment',
                  Icons.format_align_left,
                  [
                    for (final a in ['start', 'left', 'center', 'right', 'end'])
                      PopupMenuItem(value: a, child: Text(a)),
                  ],
                  (v) {
                    final rtl = selected['direction']?.value == 'rtl';
                    final physical = v == 'start'
                        ? (rtl ? 'right' : 'left')
                        : v == 'end'
                        ? (rtl ? 'left' : 'right')
                        : v;
                    draft.format(
                      q.AlignAttribute(
                        rtl && physical == 'left'
                            ? 'right'
                            : rtl && physical == 'right'
                            ? 'left'
                            : physical,
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Right-to-left paragraph',
                  icon: const Icon(Icons.format_textdirection_r_to_l, size: 20),
                  isSelected: selected['direction']?.value == 'rtl',
                  onPressed: () => draft.format(
                    selected['direction']?.value == 'rtl'
                        ? q.Attribute.fromKeyValue('direction', 'ltr')!
                        : q.Attribute.rtl,
                  ),
                ),
                toggle(
                  'Bulleted list',
                  Icons.format_list_bulleted,
                  q.Attribute.ul,
                ),
                toggle(
                  'Numbered list',
                  Icons.format_list_numbered,
                  q.Attribute.ol,
                ),
                menu<String>(
                  'Link',
                  Icons.link,
                  [
                    const PopupMenuItem(value: 'set', child: Text('Set link')),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove link'),
                    ),
                  ],
                  (value) async {
                    if (value == 'remove') {
                      draft.format(const q.LinkAttribute(null));
                      return;
                    }
                    await _setLink(context, draft);
                  },
                ),
                IconButton(
                  tooltip: 'Clear formatting',
                  icon: const Icon(Icons.format_clear, size: 20),
                  onPressed: () {
                    for (final key in [
                      'bold',
                      'italic',
                      'underline',
                      'strike',
                      'size',
                      'font',
                      'color',
                      'background',
                      'link',
                    ]) {
                      draft.format(q.Attribute.fromKeyValue(key, null)!);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Undo text edit',
                  onPressed: draft.editor.hasUndo ? draft.editor.undo : null,
                  icon: const Icon(Icons.undo, size: 20),
                ),
                IconButton(
                  tooltip: 'Redo text edit',
                  onPressed: draft.editor.hasRedo ? draft.editor.redo : null,
                  icon: const Icon(Icons.redo, size: 20),
                ),
                IconButton(
                  tooltip: 'Cancel text editing',
                  onPressed: () => draft.finish(cancel: true),
                  icon: const Icon(Icons.close, size: 20),
                ),
                IconButton(
                  tooltip: 'Done editing',
                  onPressed: () => draft.finish(),
                  icon: const Icon(Icons.check, size: 20),
                ),
              ],
            ),
          ),
          if (draft.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                draft.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}

Future<void> _setLink(BuildContext context, InlineTextDraft draft) async {
  if (draft._closed || draft.composing) return;
  final selection = draft.editor.selection;
  draft._toolbarRoutes++;
  try {
    final link = await showDialog<String>(
      context: context,
      builder: (context) => const _LinkDialog(),
    );
    if (!draft._closed && link != null && draft.editor.selection == selection) {
      draft.format(q.LinkAttribute(link));
    }
  } finally {
    draft._toolbarRoutes--;
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final text = TextEditingController();
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Text link'),
    content: TextField(
      controller: text,
      autofocus: true,
      decoration: InputDecoration(
        labelText: 'https://example.com',
        errorText: error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = text.text.trim();
          try {
            RichTextData.fromJson({
              'version': 1,
              'delta': [
                {
                  'insert': 'link',
                  'attributes': {'link': value},
                },
                {'insert': '\n'},
              ],
            });
          } on FormatException {
            setState(() => error = 'Use a valid https, http or mailto link.');
            return;
          }
          Navigator.pop(context, value);
        },
        child: const Text('Apply'),
      ),
    ],
  );
}
