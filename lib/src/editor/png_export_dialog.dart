import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../document/element.dart';
import '../geometry/geometry.dart';
import 'editor_canvas.dart';
import 'png_export.dart';
import 'project_file_gateway.dart';

Future<void> showPngExportDialog(
  BuildContext context,
  EditorCanvasController controller,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PngDialog(controller: controller),
);

class _PngDialog extends StatefulWidget {
  const _PngDialog({required this.controller});
  final EditorCanvasController controller;
  @override
  State<_PngDialog> createState() => _PngDialogState();
}

class _PngDialogState extends State<_PngDialog> {
  late final document = widget.controller.session.document;
  late final viewport = widget.controller.camera.worldViewport(
    widget.controller.viewportSize.width,
    widget.controller.viewportSize.height,
  );
  late ElementId? frameId =
      document.byId[widget.controller.selectedId]?.content
          is ExportFrameElementContent
      ? widget.controller.selectedId
      : null;
  final width = TextEditingController(), height = TextEditingController();
  bool transparent = false, busy = false, cancelled = false;
  String? message;
  @override
  void initState() {
    super.initState();
    _sizeForRegion();
  }

  Bounds2 get bounds => frameId == null
      ? viewport
      : (document.byId[frameId]!.content as ExportFrameElementContent).bounds;
  void _sizeForRegion() {
    final frame = frameId == null
        ? null
        : document.byId[frameId]!.content as ExportFrameElementContent;
    width.text = '${frame?.outputWidth ?? bounds.width.round().clamp(1, 8192)}';
    height.text =
        '${frame?.outputHeight ?? bounds.height.round().clamp(1, 8192)}';
  }

  @override
  void dispose() {
    cancelled = true;
    width.dispose();
    height.dispose();
    super.dispose();
  }

  Future<void> export() async {
    final w = int.tryParse(width.text), h = int.tryParse(height.text);
    if (w == null ||
        h == null ||
        w < 1 ||
        h < 1 ||
        w > 8192 ||
        h > 8192 ||
        w * h > 16000000) {
      setState(
        () => message =
            'Use positive dimensions, up to 8192 per side and 16 million pixels.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
      cancelled = false;
    });
    try {
      final bytes = await renderBoardPng(
        document: document,
        store: widget.controller.store,
        bounds: bounds,
        width: w,
        height: h,
        frameId: frameId,
        backgroundColor: transparent
            ? null
            : document.canvasSettings.backgroundColor,
        isCancelled: () => cancelled || !mounted,
      );
      if (!mounted || cancelled) return;
      final saved = await saveProductFile(
        bytes: bytes,
        suggestedName: document.title.isEmpty ? 'Blanko' : document.title,
        extension: 'png',
      );
      if (mounted) {
        setState(
          () => message = saved
              ? (kIsWeb ? 'PNG download started.' : 'PNG saved.')
              : 'Save cancelled.',
        );
      }
    } catch (error) {
      if (mounted && !cancelled) {
        setState(() => message = 'Could not export PNG: $error');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Export PNG'),
    content: SizedBox(
      width: 390,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: frameId?.value ?? '',
              decoration: const InputDecoration(labelText: 'Export region'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Current viewport'),
                ),
                for (final element in document.elements)
                  if (element.content is ExportFrameElementContent)
                    DropdownMenuItem(
                      value: element.id.value,
                      child: Text(
                        (element.content as ExportFrameElementContent)
                                .label
                                .isEmpty
                            ? 'Export frame · ${element.id.value}'
                            : (element.content as ExportFrameElementContent)
                                  .label,
                      ),
                    ),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      frameId = v == null || v.isEmpty ? null : ElementId(v);
                      _sizeForRegion();
                    }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in [('HD', 1920, 1080), ('4K', 3840, 2160)])
                  ActionChip(
                    label: Text(preset.$1),
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            width.text = '${preset.$2}';
                            height.text = '${preset.$3}';
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: width,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Width (px)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: height,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Height (px)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Custom dimensions scale the region to fit the output. Canvas controls and frame guides are excluded.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Transparent background'),
              value: transparent,
              onChanged: busy ? null : (v) => setState(() => transparent = v),
            ),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message!),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          cancelled = true;
          Navigator.pop(context);
        },
        child: Text(busy ? 'Cancel export' : 'Close'),
      ),
      FilledButton.icon(
        onPressed: busy || !supportsProductFiles ? null : export,
        icon: const Icon(Icons.download_outlined),
        label: const Text('Export PNG'),
      ),
    ],
  );
}
