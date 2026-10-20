import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../document/element.dart';
import '../geometry/geometry.dart';
import 'editor_text.dart';

/// Keeps text and IME composition in a local draft until Save is selected.
Future<ElementContent?> showBoardTextEditor(
  BuildContext context, {
  ElementContent? content,
  required bool sticky,
  required int color,
}) => showDialog<ElementContent>(
  context: context,
  animationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  barrierDismissible: false,
  builder: (context) =>
      _BoardTextEditor(content: content, sticky: sticky, color: color),
);

class _BoardTextEditor extends StatefulWidget {
  const _BoardTextEditor({
    required this.content,
    required this.sticky,
    required this.color,
  });

  final ElementContent? content;
  final bool sticky;
  final int color;

  @override
  State<_BoardTextEditor> createState() => _BoardTextEditorState();
}

class _BoardTextEditorState extends State<_BoardTextEditor> {
  late final TextEditingController _text;
  late final String _fontId;
  late final Bounds2 _originalBounds;
  late final ElementTextAlignment _alignment;
  late ElementTextDirection _direction;
  late double _fontSize;
  late double _width;
  late int _color;
  late int _background;

  @override
  void initState() {
    super.initState();
    final content = widget.content;
    final text = switch (content) {
      TextElementContent() => content.text,
      StickyNoteElementContent() => content.text,
      _ => '',
    };
    final style = switch (content) {
      TextElementContent() => content.style,
      StickyNoteElementContent() => content.style,
      _ => null,
    };
    _text = TextEditingController(text: text);
    _fontId = style?.fontId ?? 'editor-sans-v1';
    _fontSize = (style?.fontSize ?? 24).clamp(8, 144).toDouble();
    _color = style?.color ?? widget.color;
    _background = content is StickyNoteElementContent
        ? content.backgroundColor
        : 0xfffff3a3;
    _originalBounds = switch (content) {
      TextElementContent() => content.bounds,
      StickyNoteElementContent() => content.bounds,
      _ => Bounds2(0, 0, widget.sticky ? 240 : 320, 120),
    };
    _width = _originalBounds.width.clamp(80, 1200).toDouble();
    _direction = switch (content) {
      TextElementContent() => content.direction,
      StickyNoteElementContent() => content.direction,
      _ => ElementTextDirection.auto,
    };
    _alignment = switch (content) {
      TextElementContent() => content.alignment,
      StickyNoteElementContent() => content.alignment,
      _ => ElementTextAlignment.start,
    };
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ElementContent _content(double height) {
    final bounds = Bounds2(
      _originalBounds.left,
      _originalBounds.top,
      _originalBounds.left + _width,
      _originalBounds.top + height,
    );
    final style = ElementTextStyle(
      fontId: _fontId,
      fontSize: _fontSize,
      color: _color,
    );
    return widget.sticky
        ? StickyNoteElementContent(
            text: _text.text,
            bounds: bounds,
            style: style,
            backgroundColor: _background,
            direction: _direction,
            alignment: _alignment,
            sizing: TextSizing.autoHeight,
          )
        : TextElementContent(
            text: _text.text,
            bounds: bounds,
            style: style,
            direction: _direction,
            alignment: _alignment,
            sizing: TextSizing.autoHeight,
          );
  }

  void _save() {
    final painter = layoutElementText(_content(120));
    try {
      final height = math.max(
        widget.sticky ? 120.0 : 24.0,
        painter.height + (widget.sticky ? 24 : 0),
      );
      Navigator.of(context).pop(_content(height));
    } finally {
      painter.dispose();
    }
  }

  Widget _palette(
    String label,
    List<int> colors,
    int selected,
    ValueChanged<int> select,
  ) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    children: [
      Text('$label: '),
      for (final color in colors)
        IconButton(
          tooltip: '$label ${color.toRadixString(16)}',
          isSelected: selected == color,
          onPressed: () => setState(() => select(color)),
          style: IconButton.styleFrom(
            backgroundColor: Color(color),
            side: BorderSide(
              color: selected == color
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              width: selected == color ? 3 : 1,
            ),
            fixedSize: const Size(32, 32),
            minimumSize: const Size(32, 32),
            padding: EdgeInsets.zero,
          ),
          icon: selected == color
              ? Icon(
                  Icons.check,
                  size: 16,
                  color:
                      ThemeData.estimateBrightnessForColor(Color(color)) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : const SizedBox.shrink(),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.content == null ? 'Add' : 'Edit'} ${widget.sticky ? 'sticky note' : 'text'}',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('board-text-input'),
              controller: _text,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              maxLength: 100000,
              textCapitalization: TextCapitalization.sentences,
              textDirection: elementTextDirection(_text.text, _direction),
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const [
                  'IBM Plex Sans Arabic',
                  'Roboto',
                  'Noto Sans Arabic',
                ],
                fontSize: _fontSize,
                color: Color(_color),
                height: 1.3,
              ),
              decoration: InputDecoration(
                labelText: widget.sticky ? 'Note' : 'Text',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text('Font size: ${_fontSize.toStringAsFixed(0)}'),
            Slider(
              key: const ValueKey('board-text-font-size'),
              value: _fontSize,
              min: 8,
              max: 144,
              divisions: 136,
              label: _fontSize.toStringAsFixed(0),
              onChanged: (value) => setState(() => _fontSize = value),
            ),
            Text('Width: ${_width.toStringAsFixed(0)}'),
            Slider(
              key: const ValueKey('board-text-width'),
              value: _width,
              min: 80,
              max: 1200,
              divisions: 112,
              label: _width.toStringAsFixed(0),
              onChanged: (value) => setState(() => _width = value),
            ),
            _palette(
              'Ink',
              [0xff202d46, 0xff2463eb, 0xffdc3545, 0xff16844a],
              _color,
              (value) => _color = value,
            ),
            if (widget.sticky)
              _palette(
                'Paper',
                [0xfffff3a3, 0xffd7f5cf, 0xffd9edff, 0xffffdbe9],
                _background,
                (value) => _background = value,
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ElementTextDirection>(
              initialValue: _direction,
              decoration: const InputDecoration(labelText: 'Text direction'),
              items: const [
                DropdownMenuItem(
                  value: ElementTextDirection.auto,
                  child: Text('Automatic'),
                ),
                DropdownMenuItem(
                  value: ElementTextDirection.ltr,
                  child: Text('Left to right'),
                ),
                DropdownMenuItem(
                  value: ElementTextDirection.rtl,
                  child: Text('Right to left'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _direction = value);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: widget.sticky || _text.text.trim().isNotEmpty ? _save : null,
        child: const Text('Save'),
      ),
    ],
  );
}
