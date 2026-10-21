import 'package:flutter/material.dart';
import '../document/element.dart';
import '../geometry/geometry.dart';
import 'editor_canvas.dart';

Future<void> showFrameProperties(
  BuildContext context,
  EditorCanvasController c,
) async {
  final document = c.session.document;
  final selected = c.selectedId;
  final content = document.byId[selected]?.content;
  final (bounds, label) = switch (content) {
    ContainerFrameElementContent() => (content.bounds, content.label),
    ExportFrameElementContent() => (content.bounds, content.label),
    _ => (null, ''),
  };
  if (bounds == null) return;
  c.focusLost();
  final result = await showDialog<(String, Bounds2, int?, int?)>(
    context: context,
    builder: (_) => _FrameDialog(
      bounds: bounds,
      label: label,
      export: content is ExportFrameElementContent ? content : null,
    ),
  );
  if (result != null &&
      identical(c.session.document, document) &&
      c.selectedId == selected) {
    c.updateSelectedFrame(
      label: result.$1,
      bounds: result.$2,
      outputWidth: result.$3,
      outputHeight: result.$4,
    );
  }
}

class _FrameDialog extends StatefulWidget {
  const _FrameDialog({required this.bounds, required this.label, this.export});
  final Bounds2 bounds;
  final String label;
  final ExportFrameElementContent? export;
  @override
  State<_FrameDialog> createState() => _FrameDialogState();
}

class _FrameDialogState extends State<_FrameDialog> {
  late final name = TextEditingController(text: widget.label);
  late final width = TextEditingController(
    text: widget.bounds.width.toStringAsFixed(1),
  );
  late final height = TextEditingController(
    text: widget.bounds.height.toStringAsFixed(1),
  );
  late final pixelsW = TextEditingController(
    text:
        '${widget.export?.outputWidth ?? widget.bounds.width.round().clamp(1, 8192)}',
  );
  late final pixelsH = TextEditingController(
    text:
        '${widget.export?.outputHeight ?? widget.bounds.height.round().clamp(1, 8192)}',
  );
  String? error;
  @override
  void dispose() {
    for (final c in [name, width, height, pixelsW, pixelsH]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      keyboardType: c == name
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
    ),
  );
  void save() {
    final w = double.tryParse(width.text), h = double.tryParse(height.text);
    final pw = int.tryParse(pixelsW.text), ph = int.tryParse(pixelsH.text);
    if (w == null ||
        h == null ||
        !w.isFinite ||
        !h.isFinite ||
        w < 1 ||
        h < 1 ||
        w > 1e7 ||
        h > 1e7 ||
        (widget.export != null &&
            (pw == null ||
                ph == null ||
                pw < 1 ||
                ph < 1 ||
                pw > 8192 ||
                ph > 8192 ||
                pw * ph > 16000000))) {
      setState(
        () => error =
            'Enter positive frame sizes. PNG output supports up to 8192 per side and 16 million pixels.',
      );
      return;
    }
    Navigator.pop(context, (
      name.text.trim(),
      Bounds2(
        widget.bounds.left,
        widget.bounds.top,
        widget.bounds.left + w,
        widget.bounds.top + h,
      ),
      widget.export == null ? null : pw,
      widget.export == null ? null : ph,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.export == null ? 'Frame properties' : 'Export frame properties',
    ),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(name, 'Frame name'),
            field(width, 'Canvas width'),
            field(height, 'Canvas height'),
            if (widget.export != null) ...[
              field(pixelsW, 'Output width (px)'),
              field(pixelsH, 'Output height (px)'),
            ],
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      FilledButton(onPressed: save, child: const Text('Apply')),
    ],
  );
}
