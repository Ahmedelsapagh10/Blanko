import 'package:flutter/material.dart';
import '../document/element.dart';
import 'color_picker_widget.dart';
import 'editor_canvas.dart';

Future<void> showDrawingStyleDialog(
  BuildContext context,
  EditorCanvasController c,
) async {
  c.focusLost();
  final document = c.session.document;
  final selected = c.tool == EditorTool.select ? c.selectedDrawing : null;
  final stroke = switch (selected) {
    ShapeElementContent(:final stroke) => stroke,
    StrokeElementContent(:final style) ||
    LineElementContent(:final style) ||
    ArrowElementContent(:final style) => style,
    _ => null,
  };
  final marker = selected is StrokeElementContent
      ? selected.kind == StrokeKind.highlighter
      : c.tool == EditorTool.highlighter;
  final pen =
      selected is StrokeElementContent || c.tool == EditorTool.pen || marker;
  final shape =
      selected is ShapeElementContent ||
      (selected == null &&
          [
            EditorTool.rectangle,
            EditorTool.ellipse,
            EditorTool.triangle,
          ].contains(c.tool));
  final arrow =
      selected is ArrowElementContent ||
      (selected == null && c.tool == EditorTool.arrow);
  var width = stroke?.width ?? c.activeStrokeWidth;
  var opacity = ((stroke?.color ?? c.activeStrokeColor) >>> 24) / 255;
  var markerOpacity = selected is StrokeElementContent
      ? (selected.highlighterOpacity ?? .28) * opacity
      : c.highlighterOpacity;
  if (marker) opacity = 1;
  final initialFill = selected is ShapeElementContent
      ? selected.fillColor
      : c.fillColor;
  var fill = initialFill != null;
  var fillOpacity = ((initialFill ?? 0xff2563eb) >>> 24) / 255;
  var dashed = stroke?.dashed ?? c.dashed;
  var heads = selected is ArrowElementContent ? selected.heads : c.arrowHeads;
  String hex(int value) =>
      (value & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase();
  final strokeHex = TextEditingController(
    text: hex(stroke?.color ?? c.activeColor),
  );
  final fillHex = TextEditingController(text: hex(initialFill ?? 0xff2563eb));
  String? error;
  try {
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(marker ? 'Highlighter style' : 'Drawing style'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ColorPickerWidget(
                    controller: strokeHex,
                    labelText: 'Stroke color (RRGGBB)',
                    errorText: error,
                    isHighlighter: marker,
                    onColorChanged: (_) => setState(() => error = null),
                  ),
                  const SizedBox(height: 12),
                  Text('Width: ${width.toStringAsFixed(1)}'),
                  Slider(
                    min: 1,
                    max: marker ? 100 : 48,
                    value: width.clamp(1, marker ? 100 : 48),
                    onChanged: (v) => setState(() => width = v),
                  ),
                  if (!marker) ...[
                    Text('Stroke opacity: ${(opacity * 100).round()}%'),
                    Slider(
                      value: opacity,
                      onChanged: (v) => setState(() => opacity = v),
                    ),
                  ],
                  if (marker) ...[
                    Text('Marker opacity: ${(markerOpacity * 100).round()}%'),
                    Slider(
                      value: markerOpacity,
                      onChanged: (v) => setState(() => markerOpacity = v),
                    ),
                  ],
                  if (shape) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Fill'),
                      value: fill,
                      onChanged: (v) => setState(() => fill = v),
                    ),
                    if (fill) ...[
                      ColorPickerWidget(
                        controller: fillHex,
                        labelText: 'Fill color (RRGGBB)',
                        errorText: error,
                        isHighlighter: false,
                        onColorChanged: (_) => setState(() => error = null),
                      ),
                      const SizedBox(height: 8),
                      Text('Fill opacity: ${(fillOpacity * 100).round()}%'),
                      Slider(
                        value: fillOpacity,
                        onChanged: (v) => setState(() => fillOpacity = v),
                      ),
                    ],
                  ],
                  if (!pen)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dashed stroke'),
                      value: dashed,
                      onChanged: (v) => setState(() => dashed = v),
                    ),
                  if (arrow)
                    DropdownButtonFormField<ArrowHeadStyle>(
                      initialValue: heads,
                      decoration: const InputDecoration(
                        labelText: 'Arrowheads',
                      ),
                      items: [
                        for (final h in ArrowHeadStyle.values)
                          DropdownMenuItem(
                            value: h,
                            child: Text(switch (h) {
                              ArrowHeadStyle.none => 'None',
                              ArrowHeadStyle.start => 'Start',
                              ArrowHeadStyle.end => 'End',
                              ArrowHeadStyle.both => 'Both ends',
                            }),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => heads = v);
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                int? parse(String text) =>
                    RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(text.trim())
                    ? (0xff000000 |
                          int.parse(
                            text.trim().replaceFirst('#', ''),
                            radix: 16,
                          ))
                    : null;
                final color = parse(strokeHex.text),
                    fillColor = fill ? parse(fillHex.text) : null;
                if (color == null || (fill && fillColor == null)) {
                  setState(() => error = 'Use six hexadecimal digits.');
                  return;
                }
                if (identical(document, c.session.document) && c.inputEnabled) {
                  c.applyDrawingStyle(
                    strokeColor: color,
                    width: width,
                    opacity: opacity,
                    fill: fillColor == null
                        ? null
                        : EditorCanvasController.withOpacity(
                            fillColor,
                            fillOpacity,
                          ),
                    dash: dashed,
                    heads: heads,
                    markerOpacity: markerOpacity,
                    applyFill: shape,
                    applyDash: !pen,
                    applyHeads: arrow,
                    applyMarkerOpacity: marker,
                  );
                }
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
  } finally {
    strokeHex.dispose();
    fillHex.dispose();
  }
}
