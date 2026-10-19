import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../geometry/geometry.dart';
import 'benchmark_telemetry.dart';
import 'scene_renderer.dart';

final class BenchmarkPainter extends CustomPainter {
  BenchmarkPainter({
    required this.renderer,
    required this.viewport,
    required this.zoom,
    required this.selected,
    required this.movingIndex,
    required this.moveDelta,
    required this.telemetry,
    this.includeText = true,
    this.includeImages = true,
    this.optimized = false,
    this.devicePixelRatio = 1,
  }) : revision = renderer.revision,
       super(repaint: Listenable.merge([moveDelta, renderer.cacheChanges]));

  final SceneRenderer renderer;
  final Bounds2 viewport;
  final double zoom;
  final double devicePixelRatio;
  final String? selected;
  final int? movingIndex;
  final ValueListenable<Point2> moveDelta;
  final BenchmarkTelemetry telemetry;
  final bool includeText;
  final bool includeImages;
  final bool optimized;
  final int revision;

  List<int> queryVisible() {
    final clock = telemetry.recording ? (Stopwatch()..start()) : null;
    final visible = renderer.index.query(viewport);
    final moving = movingIndex;
    if (moving != null) {
      final delta = moveDelta.value;
      final bounds = Transform2.translation(
        delta.x,
        delta.y,
      ).mapBounds(renderer.scene.paintOrder[moving].worldBounds);
      visible.remove(moving);
      if (bounds.intersects(viewport)) {
        visible.add(moving);
        visible.sort();
      }
    }
    if (clock != null) telemetry.query.add(clock.elapsedMicroseconds);
    return visible;
  }

  void _worldCanvas(Canvas canvas, void Function() paint) {
    canvas.save();
    canvas.scale(zoom);
    canvas.clipRect(Rect.fromLTWH(0, 0, viewport.width, viewport.height));
    paint();
    canvas.restore();
  }

  void paintBackground(Canvas canvas) => _worldCanvas(canvas, () {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, viewport.width, viewport.height),
      Paint()..color = const Color(0xfff8fafc),
    );
    final spacing = math
        .pow(10, (math.log(32 / zoom) / math.ln10).ceil())
        .toDouble();
    final grid = Path();
    for (
      var x = (viewport.left / spacing).floor() * spacing;
      x <= viewport.right;
      x += spacing
    ) {
      grid
        ..moveTo(x - viewport.left, 0)
        ..lineTo(x - viewport.left, viewport.height);
    }
    for (
      var y = (viewport.top / spacing).floor() * spacing;
      y <= viewport.bottom;
      y += spacing
    ) {
      grid
        ..moveTo(0, y - viewport.top)
        ..lineTo(viewport.width, y - viewport.top);
    }
    canvas.drawPath(
      grid,
      Paint()
        ..color = const Color(0xffe2e8f0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / zoom,
    );
  });

  void paintElements(Canvas canvas, List<int> visible, {bool? useOptimized}) =>
      _worldCanvas(canvas, () {
        renderer.paint(
          canvas,
          visible,
          movingIndex: movingIndex,
          moveDelta: moveDelta.value,
          includeText: includeText,
          includeImages: includeImages,
          worldOrigin: Point2(viewport.left, viewport.top),
          zoom: zoom,
          optimized: useOptimized ?? optimized,
          viewport: viewport,
          devicePixelRatio: devicePixelRatio,
        );
      });

  void paintSelection(Canvas canvas, List<int> visible) {
    if (selected == null) return;
    _worldCanvas(canvas, () {
      for (final index in visible) {
        final entry = renderer.scene.paintOrder[index];
        if (entry.node.id != selected) continue;
        final delta = moveDelta.value;
        final bounds = index == movingIndex
            ? Transform2.translation(
                delta.x,
                delta.y,
              ).mapBounds(entry.worldBounds)
            : entry.worldBounds;
        canvas.drawRect(
          Rect.fromLTRB(
            bounds.left - viewport.left,
            bounds.top - viewport.top,
            bounds.right - viewport.left,
            bounds.bottom - viewport.top,
          ),
          Paint()
            ..color = const Color(0xffe11d48)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / zoom,
        );
        break;
      }
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final visible = queryVisible();
    final clock = telemetry.recording ? (Stopwatch()..start()) : null;
    paintBackground(canvas);
    paintElements(canvas, visible);
    if (telemetry.recording && renderer.lastPaintUsedOverview) {
      telemetry.overviewPaints++;
    }
    paintSelection(canvas, visible);
    if (clock != null) telemetry.recordPaint.add(clock.elapsedMicroseconds);
    telemetry.painted(visible.length);
  }

  @override
  bool shouldRepaint(BenchmarkPainter old) =>
      renderer != old.renderer ||
      revision != old.revision ||
      viewport != old.viewport ||
      zoom != old.zoom ||
      devicePixelRatio != old.devicePixelRatio ||
      selected != old.selected ||
      movingIndex != old.movingIndex ||
      includeText != old.includeText ||
      includeImages != old.includeImages ||
      optimized != old.optimized;
}

/// The existing painter's input/grid/selection contract with composited content.
final class BenchmarkLayerCanvas extends LeafRenderObjectWidget {
  const BenchmarkLayerCanvas({super.key, required this.painter});
  final BenchmarkPainter painter;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LayerCanvasBox(painter);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) {
    (renderObject as _LayerCanvasBox).painter = painter;
  }
}

final class _LayerCanvasBox extends RenderBox {
  _LayerCanvasBox(this._painter);
  BenchmarkPainter _painter;
  set painter(BenchmarkPainter value) {
    if (identical(value, _painter)) return;
    if (attached) _painter.removeListener(markNeedsPaint);
    final repaint = value.shouldRepaint(_painter);
    _painter = value;
    if (attached) _painter.addListener(markNeedsPaint);
    if (repaint) markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _painter.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _painter.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : 0,
      constraints.hasBoundedHeight ? constraints.maxHeight : 0,
    ),
  );
  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final painter = _painter;
    final visible = painter.queryVisible();
    final clock = painter.telemetry.recording ? (Stopwatch()..start()) : null;
    void atOffset(void Function(Canvas) callback) {
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      callback(canvas);
      canvas.restore();
    }

    atOffset(painter.paintBackground);
    final retained =
        painter.optimized &&
        painter.includeText &&
        painter.includeImages &&
        painter.renderer.paintLayers(
          context,
          offset,
          visible,
          painter.viewport,
          painter.zoom,
          painter.devicePixelRatio,
          movingIndex: painter.movingIndex,
          paintDirect: (indices) => atOffset(
            (canvas) =>
                painter.paintElements(canvas, indices, useOptimized: false),
          ),
        );
    if (!retained) atOffset((canvas) => painter.paintElements(canvas, visible));
    atOffset((canvas) => painter.paintSelection(canvas, visible));
    if (clock != null) {
      painter.telemetry.recordPaint.add(clock.elapsedMicroseconds);
    }
    painter.telemetry.painted(visible.length);
  }
}
