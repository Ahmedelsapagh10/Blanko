import 'dart:math' as math;
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../geometry/geometry.dart';
import '../spatial/spatial_grid.dart';
import 'benchmark_fixtures.dart';
import 'benchmark_fonts.dart';
import 'benchmark_scene.dart';
import 'scene_tile_cache.dart';
import 'scene_picture_cache.dart';
import 'scene_layer_cache.dart';

final class SceneRenderer {
  SceneRenderer._(
    BenchmarkScene scene,
    List<_RenderEntry> entries,
    this._images,
  ) : _entries = entries,
      _hasText = entries.any((entry) => entry.text != null),
      _scene = scene,
      index = SpatialGrid(scene.paintOrder.map((entry) => entry.worldBounds));

  static Future<SceneRenderer> create(
    BenchmarkScene scene, {
    int imageSide = 1024,
    bool cacheOverview = false,
    bool cacheTiles = false,
    bool recoverTiles = false,
    bool repairTiles = false,
    bool retainRanges = false,
    bool retainLayers = false,
  }) async {
    if (retainRanges && retainLayers) {
      throw ArgumentError('Choose either vector ranges or retained layers.');
    }
    if (imageSide < 1 || imageSide > 2048) {
      throw ArgumentError.value(imageSide, 'imageSide');
    }
    if (!BenchmarkFonts.instance.isReady) {
      await BenchmarkFonts.instance.ensureLoaded();
    }
    final images = <String, ui.Image>{};
    final entries = <_RenderEntry>[];
    final prepareClock = Stopwatch()..start();
    final entryTimes = <String, int>{};
    try {
      final assetIds = scene.paintOrder
          .map((entry) => entry.node.content)
          .whereType<ImageContent>()
          .map((content) => content.assetId)
          .toSet();
      for (final id in assetIds) {
        final number = int.tryParse(id.replaceFirst('image-', ''));
        if (number == null ||
            number < 0 ||
            number >= BenchmarkFixture.imageAssetCount) {
          throw ArgumentError('Unknown synthetic image: $id');
        }
        images[id] = await _createImage(number, imageSide);
      }
      final imageMicros = prepareClock.elapsedMicroseconds;
      developer.Timeline.startSync('phase01.prepareEntries');
      try {
        for (final resolved in scene.paintOrder) {
          final clock = Stopwatch()..start();
          entries.add(_RenderEntry(resolved));
          final kind = resolved.node.content.runtimeType.toString();
          entryTimes.update(
            kind,
            (v) => v + clock.elapsedMicroseconds,
            ifAbsent: () => clock.elapsedMicroseconds,
          );
        }
      } finally {
        developer.Timeline.finishSync();
      }
      final indexClock = Stopwatch()..start();
      final renderer = SceneRenderer._(scene, entries, images);
      final indexMicros = indexClock.elapsedMicroseconds;
      renderer.preparation = {
        'imageMicros': imageMicros,
        'indexMicros': indexMicros,
        'entryMicrosByType': entryTimes,
      };
      if (retainLayers) {
        renderer._layers = SceneLayerCache(
          renderer._recordLayerRange,
          (i) => renderer._entries[i].resolved.worldBounds,
        );
      } else if (retainRanges) {
        renderer._ranges = ScenePictureCache(
          renderer._recordRange,
          (i) => renderer._entries[i].resolved.worldBounds,
        );
      } else if (cacheTiles) {
        renderer._tiles = SceneTileCache(
          renderer._recordTile,
          recovery: recoverTiles,
          repair: repairTiles && recoverTiles ? renderer._repairTile : null,
        );
        renderer._tiles!.changed.addListener(
          () => renderer.cacheChanges.value++,
        );
      } else if (cacheOverview) {
        await renderer.prepareOverview();
      }
      return renderer;
    } catch (_) {
      for (final entry in entries) {
        entry.text?.dispose();
      }
      for (final image in images.values) {
        image.dispose();
      }
      rethrow;
    }
  }

  final cacheChanges = ValueNotifier<int>(0);
  SceneTileCache? _tiles;
  ScenePictureCache? _ranges;
  SceneLayerCache? _layers;
  Map<String, Object?>? get layerStatistics => _layers?.statistics;
  Map<String, Object?>? get retainedStatistics => _ranges?.statistics;

  void setRetainedActiveIndices(Iterable<int> indices) {
    if (_disposed) throw StateError('Renderer has been disposed.');
    final active = indices.toSet();
    if (active.any((i) => i < 0 || i >= _entries.length)) {
      throw ArgumentError('Invalid active paint index.');
    }
    _ranges?.setActiveIndices(active);
    _layers?.setActiveIndices(active);
  }

  void resetRetained() {
    if (_disposed) throw StateError('Renderer has been disposed.');
    _ranges?.clear();
    _layers?.clear();
  }

  ui.Picture _recordLayerRange(List<int> indices, Bounds2 view, double zoom) {
    final recorder = ui.PictureRecorder();
    final screen = ui.Rect.fromLTWH(
      0,
      0,
      view.width * zoom,
      view.height * zoom,
    );
    try {
      // Leave AA coverage to the composited viewport clip. A second exact
      // clip changes edge alpha when the widget lands between device pixels.
      final canvas = ui.Canvas(recorder, screen.inflate(2))
        ..clipRect(screen.inflate(2), doAntiAlias: false)
        ..scale(zoom);
      _paintDirect(canvas, indices, worldOrigin: Point2(view.left, view.top));
    } catch (_) {
      recorder.endRecording().dispose();
      rethrow;
    }
    return recorder.endRecording();
  }

  bool paintLayers(
    PaintingContext context,
    ui.Offset offset,
    List<int> visible,
    Bounds2 viewport,
    double zoom,
    double devicePixelRatio, {
    int? movingIndex,
    required void Function(List<int>) paintDirect,
  }) {
    if (_disposed) throw StateError('Renderer has been disposed.');
    return _layers?.paint(
          context,
          offset,
          visible,
          viewport,
          zoom,
          devicePixelRatio,
          movingIndex: movingIndex,
          paintDirect: paintDirect,
        ) ??
        false;
  }

  ui.Picture _recordRange(List<int> indices, Point2 origin) {
    final recorder = ui.PictureRecorder();
    try {
      _paintDirect(ui.Canvas(recorder), indices, worldOrigin: origin);
    } catch (_) {
      recorder.endRecording().dispose();
      rethrow;
    }
    return recorder.endRecording();
  }

  Map<String, Object?>? get tileStatistics => _tiles == null
      ? null
      : {
          ..._tiles!.statistics,
          'repairReplayedEntries': repairReplayedEntries,
          'textResamplingFallbacks': _textResamplingFallbacks,
        };
  Future<void> prepareTiles(Bounds2 view, double pixelScale) async {
    await _tiles?.prepare(view, pixelScale);
  }

  int get textLayoutCount => _entries.where((e) => e.text != null).length;
  int repairReplayedEntries = 0;
  ui.Picture _repairTile(
    Bounds2 bounds,
    double scale,
    ui.Image base,
    List<Bounds2> damage,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final dirty = ui.Path();
    for (final area in damage) {
      dirty.addRect(
        ui.Rect.fromLTRB(
          1 + (area.left - bounds.left) * scale,
          1 + (area.top - bounds.top) * scale,
          1 + (area.right - bounds.left) * scale,
          1 + (area.bottom - bounds.top) * scale,
        ),
      );
    }
    canvas.save();
    for (final area in damage) {
      canvas.clipRect(
        ui.Rect.fromLTRB(
          1 + (area.left - bounds.left) * scale,
          1 + (area.top - bounds.top) * scale,
          1 + (area.right - bounds.left) * scale,
          1 + (area.bottom - bounds.top) * scale,
        ),
        clipOp: ui.ClipOp.difference,
        doAntiAlias: false,
      );
    }
    canvas.drawImage(base, ui.Offset.zero, ui.Paint());
    canvas.restore();
    canvas.clipPath(dirty, doAntiAlias: false);
    canvas.translate(1, 1);
    canvas.scale(scale);
    final affected = <int>{
      for (final area in damage) ...index.query(area.inflate(1 / scale)),
    }.toList()..sort();
    repairReplayedEntries += affected.length;
    _paintDirect(
      canvas,
      affected,
      worldOrigin: Point2(bounds.left, bounds.top),
    );
    return recorder.endRecording();
  }

  ui.Picture _recordTile(Bounds2 bounds, double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..translate(1, 1)
      ..scale(scale);
    final padded = bounds.inflate(1 / scale);
    developer.Timeline.startSync('phase02.recordTile');
    try {
      _paintDirect(
        canvas,
        index.query(padded),
        worldOrigin: Point2(bounds.left, bounds.top),
      );
    } finally {
      developer.Timeline.finishSync();
    }
    return recorder.endRecording();
  }

  BenchmarkScene _scene;
  BenchmarkScene get scene => _scene;
  final SpatialGrid index;
  final List<_RenderEntry> _entries;
  final bool _hasText;
  int _textResamplingFallbacks = 0;
  String? lastTileFallbackReason;
  final Map<String, ui.Image> _images;
  bool _disposed = false;
  int _revision = 0;
  int get revision => _revision;
  int lastHitCandidates = 0;
  int lastIndexUpdateMicros = 0;
  int lastSynchronizedEntries = 0;
  int lastCacheInvalidationMicros = 0;
  int lastValidationMicros = 0;
  Map<String, Object?> preparation = const {};
  bool get isDisposed => _disposed;
  ui.Image? _overview;
  Future<void>? _overviewPending;
  Point2 _overviewOrigin = Point2.zero;
  double _overviewScale = 1;
  int _overviewGeneration = 0;
  int overviewPrepareMicros = 0;
  int overviewBuilds = 0;
  bool lastPaintUsedOverview = false;
  int get overviewBytes =>
      _overview == null ? 0 : _overview!.width * _overview!.height * 4;
  int get ownedImageHandles => _disposed
      ? 0
      : _images.length + (_overview == null ? 0 : 1) + (_tiles?.handles ?? 0);
  int get ownedParagraphs =>
      _disposed ? 0 : _entries.where((e) => e.text != null).length;
  void _invalidateCaches() {
    _overviewGeneration++;
    _overview?.dispose();
    _overview = null;
  }

  /// One raster, at most 2048² pixels / 16 MiB logical RGBA. Sparse worlds skip
  /// this cache. Content is composited in paint order; zoom-in stays vector.
  Future<void> prepareOverview() {
    return _overviewPending ??= _buildOverview().whenComplete(() {
      _overviewPending = null;
    });
  }

  Future<void> _buildOverview() async {
    if (_disposed || _overview != null || scene.paintOrder.isEmpty) return;
    final generation = ++_overviewGeneration;
    final clock = Stopwatch()..start();
    var bounds = scene.paintOrder.first.worldBounds;
    for (final entry in scene.paintOrder.skip(1)) {
      final b = entry.worldBounds;
      bounds = Bounds2(
        math.min(bounds.left, b.left),
        math.min(bounds.top, b.top),
        math.max(bounds.right, b.right),
        math.max(bounds.bottom, b.bottom),
      );
    }
    if (bounds.width > 8192 || bounds.height > 8192) return;
    final scale = math.min(
      1.0,
      math.min(
        2044 / math.max(1, bounds.width),
        2044 / math.max(1, bounds.height),
      ),
    );
    final origin = Point2(bounds.left - 2 / scale, bounds.top - 2 / scale);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    developer.Timeline.startSync('phase01.recordOverview');
    try {
      _paintDirect(
        canvas,
        List.generate(_entries.length, (i) => i),
        worldOrigin: origin,
      );
    } finally {
      developer.Timeline.finishSync();
    }
    final picture = recorder.endRecording();
    ui.Image image;
    try {
      image = await picture.toImage(
        math.min(2048, (bounds.width * scale).ceil() + 4),
        math.min(2048, (bounds.height * scale).ceil() + 4),
      );
    } finally {
      picture.dispose();
    }
    overviewPrepareMicros = clock.elapsedMicroseconds;
    if (_disposed || generation != _overviewGeneration) {
      image.dispose();
      return;
    }
    _overview = image;
    _overviewOrigin = origin;
    _overviewScale = scale;
    overviewBuilds++;
  }

  /// Refresh geometry caches after the session commits an immutable scene.
  /// Content and paint order are fixed for this rendering feasibility spike.
  void synchronize(BenchmarkScene next) {
    if (_disposed) throw StateError('Renderer has been disposed.');
    if (identical(next, scene)) return;
    if (next.paintOrder.length != scene.paintOrder.length) {
      throw ArgumentError('Scene structure changed.');
    }
    final delta = next.delta;
    final indices =
        delta != null && identical(delta.baseIdentity, scene.identity)
        ? delta.paintIndices
        : List<int>.generate(next.paintOrder.length, (i) => i);
    lastSynchronizedEntries = indices.length;
    final validationClock = Stopwatch()..start();
    for (final i in indices) {
      final before = scene.paintOrder[i].node;
      final after = next.paintOrder[i].node;
      if (before.id != after.id ||
          before.content != after.content ||
          before.localBounds != after.localBounds ||
          before.strokeWidth != after.strokeWidth ||
          before.color != after.color) {
        throw ArgumentError('Only transforms can change during the spike.');
      }
      // Validate all new index ranges before mutating any cache.
      index.validateBounds(next.paintOrder[i].worldBounds);
    }
    lastValidationMicros = validationClock.elapsedMicroseconds;
    final invalidationClock = Stopwatch()..start();
    _ranges?.invalidate(indices);
    _layers?.invalidate(indices);
    _tiles?.invalidate([
      for (final i in indices) ...[
        scene.paintOrder[i].worldBounds,
        next.paintOrder[i].worldBounds,
      ],
    ]);
    lastCacheInvalidationMicros = invalidationClock.elapsedMicroseconds;
    lastIndexUpdateMicros = 0;
    for (final i in indices) {
      final resolved = next.paintOrder[i];
      if (resolved.worldTransform != _entries[i].resolved.worldTransform) {
        _entries[i].setTransform(resolved);
        final clock = Stopwatch()..start();
        index.update(i, resolved.worldBounds);
        lastIndexUpdateMicros += clock.elapsedMicroseconds;
      }
    }
    _invalidateCaches();
    _scene = next;
    _revision++;
  }

  int get imageBytes => _images.values.fold(
    0,
    (sum, image) => sum + image.width * image.height * 4,
  );

  void paint(
    ui.Canvas canvas,
    List<int> visible, {
    int? movingIndex,
    Point2 moveDelta = Point2.zero,
    bool includeText = true,
    bool includeImages = true,
    Point2 worldOrigin = Point2.zero,
    double zoom = 1,
    bool optimized = false,
    Bounds2? viewport,
    double devicePixelRatio = 1,
  }) {
    if (_disposed) throw StateError('Renderer has been disposed.');
    lastPaintUsedOverview = false;
    lastTileFallbackReason = null;
    if (optimized && _ranges != null && includeText && includeImages) {
      if (_ranges!.paint(
        canvas,
        visible,
        worldOrigin,
        movingIndex: movingIndex,
        paintDirect: (indices) => _paintDirect(
          canvas,
          indices,
          movingIndex: movingIndex,
          moveDelta: moveDelta,
          worldOrigin: worldOrigin,
        ),
      )) {
        return;
      }
    }
    if (optimized &&
        _tiles != null &&
        viewport != null &&
        movingIndex == null &&
        includeText &&
        includeImages) {
      final pixelScale = zoom * devicePixelRatio;
      if (_hasText &&
          pixelScale != math.pow(2, SceneTileCache.bucket(pixelScale))) {
        // Resampling a small glyph from another raster scale changes its ink.
        // Fall back as a complete ordered scene, never overlay text out of order.
        _textResamplingFallbacks++;
        lastTileFallbackReason = 'text raster scale differs from display scale';
        _paintDirect(canvas, visible, worldOrigin: worldOrigin);
        return;
      }
      if (_tiles!.paint(
        canvas,
        viewport,
        zoom * devicePixelRatio,
        worldOrigin,
        paintMissing: (areas) {
          // Merge before drawing: elements spanning several missing tiles must
          // be recorded only once, in authoritative paint order.
          final affected = <int>{
            for (final bounds in areas)
              ...index.query(bounds.inflate(1 / (zoom * devicePixelRatio))),
          }.toList()..sort();
          _paintDirect(canvas, affected, worldOrigin: worldOrigin);
        },
      )) {
        return;
      }
    }
    final overview = _overview;
    if (optimized &&
        movingIndex == null &&
        includeText &&
        includeImages &&
        overview != null &&
        zoom <= _overviewScale) {
      lastPaintUsedOverview = true;
      canvas.save();
      canvas.translate(
        _overviewOrigin.x - worldOrigin.x,
        _overviewOrigin.y - worldOrigin.y,
      );
      canvas.scale(1 / _overviewScale);
      canvas.drawImage(
        overview,
        ui.Offset.zero,
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      canvas.restore();
      return;
    }
    _paintDirect(
      canvas,
      visible,
      movingIndex: movingIndex,
      moveDelta: moveDelta,
      worldOrigin: worldOrigin,
      includeText: includeText,
      includeImages: includeImages,
    );
  }

  void _paintDirect(
    ui.Canvas canvas,
    List<int> visible, {
    int? movingIndex,
    Point2 moveDelta = Point2.zero,
    bool includeText = true,
    bool includeImages = true,
    Point2 worldOrigin = Point2.zero,
  }) {
    if (_disposed) throw StateError('Renderer has been disposed.');
    for (final i in visible) {
      final entry = _entries[i];
      final node = entry.resolved.node;
      if ((!includeText && node.content is TextContent) ||
          (!includeImages && node.content is ImageContent)) {
        continue;
      }
      canvas.save();
      if (i == movingIndex) canvas.translate(moveDelta.x, moveDelta.y);
      // Subtract in Dart doubles before the engine converts matrices to floats.
      entry.matrix[12] = entry.resolved.worldTransform.tx - worldOrigin.x;
      entry.matrix[13] = entry.resolved.worldTransform.ty - worldOrigin.y;
      canvas.transform(entry.matrix);
      final bounds = _rect(node.localBounds);
      switch (node.content) {
        case ShapeContent():
          canvas.drawPath(entry.path!, entry.fill);
          canvas.drawPath(entry.path!, entry.stroke);
        case StrokeContent():
          canvas.drawPath(entry.path!, entry.stroke);
        case ArrowContent():
          canvas.drawPath(entry.path!, entry.stroke);
        case TextContent(:final sticky):
          if (sticky) {
            canvas.drawRRect(
              ui.RRect.fromRectAndRadius(bounds, const ui.Radius.circular(4)),
              entry.fill,
            );
          }
          canvas.clipRect(bounds);
          entry.text!.paint(canvas, ui.Offset(bounds.left + 8, bounds.top + 8));
        case ImageContent(:final assetId):
          final image = _images[assetId]!;
          canvas.drawImageRect(
            image,
            ui.Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            bounds,
            entry.fill,
          );
        case GroupContent():
          break;
      }
      canvas.restore();
    }
  }

  String? hitTest(Point2 worldPoint, {required double worldTolerance}) {
    if (_disposed) throw StateError('Renderer has been disposed.');
    final candidates = index.query(
      Bounds2(
        worldPoint.x,
        worldPoint.y,
        worldPoint.x,
        worldPoint.y,
      ).inflate(worldTolerance),
    );
    lastHitCandidates = candidates.length;
    for (final i in candidates.reversed) {
      final entry = _entries[i];
      final inverse = entry.resolved.worldInverse;
      final local = inverse.apply(worldPoint);
      final tolerance = worldTolerance * inverse.maximumScale;
      if (entry.hitTest(local, tolerance)) return entry.resolved.node.id;
    }
    return null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ranges?.dispose();
    _layers?.dispose();
    _tiles?.dispose();
    cacheChanges.dispose();
    _invalidateCaches();
    for (final entry in _entries) {
      entry.text?.dispose();
    }
    for (final image in _images.values) {
      image.dispose();
    }
  }

  static Future<ui.Image> _createImage(int number, int side) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = side.toDouble();
    const colors = [
      ui.Color(0xff0f766e),
      ui.Color(0xff1d4ed8),
      ui.Color(0xff7c3aed),
      ui.Color(0xffbe123c),
    ];
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..color = colors[number],
    );
    final paint = ui.Paint()..color = const ui.Color(0x66ffffff);
    for (var i = 0; i < 24; i++) {
      canvas.drawCircle(
        ui.Offset(size * (i % 6 + 0.5) / 6, size * (i ~/ 6 + 0.5) / 4),
        size * (0.025 + (i % 3) * 0.015),
        paint,
      );
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(side, side);
    } finally {
      picture.dispose();
    }
  }
}

final class _RenderEntry {
  _RenderEntry(this.resolved) {
    final node = resolved.node;
    final transform = resolved.worldTransform;
    matrix = Float64List.fromList([
      transform.a,
      transform.b,
      0,
      0,
      transform.c,
      transform.d,
      0,
      0,
      0,
      0,
      1,
      0,
      transform.tx,
      transform.ty,
      0,
      1,
    ]);
    final bounds = _rect(node.localBounds);
    fill = ui.Paint()..color = ui.Color(node.color).withValues(alpha: 0.14);
    stroke = ui.Paint()
      ..color = ui.Color(node.color)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = node.strokeWidth
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;
    switch (node.content) {
      case ShapeContent(:final kind):
        path = ui.Path();
        switch (kind) {
          case ShapeKind.rectangle:
            path!.addRect(bounds);
          case ShapeKind.ellipse:
            path!.addOval(bounds);
          case ShapeKind.triangle:
            path!
              ..moveTo(bounds.center.dx, bounds.top)
              ..lineTo(bounds.right, bounds.bottom)
              ..lineTo(bounds.left, bounds.bottom)
              ..close();
        }
      case StrokeContent(:final points, :final highlighter):
        // A single polyline draw also gives the eraser/hit-test the same geometry.
        path = ui.Path()..moveTo(points.first.x, points.first.y);
        if (points.length == 1) {
          path!.lineTo(points.first.x + 0.001, points.first.y);
        } else {
          for (final point in points.skip(1)) {
            path!.lineTo(point.x, point.y);
          }
        }
        if (highlighter) stroke.color = stroke.color.withValues(alpha: 0.28);
      case ArrowContent(:final points):
        arrowPoints = points;
        path = ui.Path()..moveTo(points.first.x, points.first.y);
        for (final point in arrowPoints!.skip(1)) {
          path!.lineTo(point.x, point.y);
        }
      case TextContent(:final text, :final rtl):
        fill.color = const ui.Color(0xffffeb99);
        this.text = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(
              color: ui.Color(0xff172033),
              fontSize: 14,
              fontFamily: BenchmarkFonts.latin,
              fontFamilyFallback: [BenchmarkFonts.arabic],
              height: 1.2,
            ),
          ),
          textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
          maxLines: 3,
        )..layout(maxWidth: math.max(1, bounds.width - 16));
      case ImageContent():
        fill.color = const ui.Color(0xffffffff);
        fill.filterQuality = ui.FilterQuality.low;
      case GroupContent():
        break;
    }
  }

  void setTransform(ResolvedNode value) {
    resolved = value;
    final transform = value.worldTransform;
    matrix[0] = transform.a;
    matrix[1] = transform.b;
    matrix[4] = transform.c;
    matrix[5] = transform.d;
    matrix[12] = transform.tx;
    matrix[13] = transform.ty;
  }

  ResolvedNode resolved;
  late final Float64List matrix;
  late final ui.Paint fill;
  late final ui.Paint stroke;
  ui.Path? path;
  TextPainter? text;
  List<Point2>? arrowPoints;

  bool hitTest(Point2 point, double tolerance) {
    final node = resolved.node;
    switch (node.content) {
      case StrokeContent(:final points):
        return _hitsPolyline(point, points, tolerance + node.strokeWidth / 2);
      case ArrowContent():
        return _hitsPolyline(
          point,
          arrowPoints!,
          tolerance + node.strokeWidth / 2,
        );
      case ShapeContent():
        if (path!.contains(ui.Offset(point.x, point.y))) return true;
        // Check the actual outline rather than the rotated axis-aligned bounds.
        final outline = path!.computeMetrics();
        for (final metric in outline) {
          final steps = math.max(8, (metric.length / 4).ceil());
          var previous = metric.getTangentForOffset(0)!.position;
          for (var i = 1; i <= steps; i++) {
            final next = metric
                .getTangentForOffset(metric.length * i / steps)!
                .position;
            if (_segmentDistance(
                  point,
                  Point2(previous.dx, previous.dy),
                  Point2(next.dx, next.dy),
                ) <=
                tolerance + node.strokeWidth / 2) {
              return true;
            }
            previous = next;
          }
        }
        return false;
      case TextContent():
      case ImageContent():
        return node.localBounds.inflate(tolerance).contains(point);
      case GroupContent():
        return false;
    }
  }
}

bool _hitsPolyline(Point2 point, List<Point2> points, double tolerance) {
  if (points.length == 1) return point.distanceTo(points.first) <= tolerance;
  for (var i = 1; i < points.length; i++) {
    if (_segmentDistance(point, points[i - 1], points[i]) <= tolerance) {
      return true;
    }
  }
  return false;
}

double _segmentDistance(Point2 point, Point2 start, Point2 end) {
  final delta = end - start;
  final lengthSquared = delta.x * delta.x + delta.y * delta.y;
  if (lengthSquared == 0) return point.distanceTo(start);
  final relative = point - start;
  final factor = ((relative.x * delta.x + relative.y * delta.y) / lengthSquared)
      .clamp(0.0, 1.0);
  return point.distanceTo(start + delta * factor);
}

ui.Rect _rect(Bounds2 bounds) =>
    ui.Rect.fromLTRB(bounds.left, bounds.top, bounds.right, bounds.bottom);
