import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../geometry/geometry.dart';
import 'frame_samples.dart';

/// On-screen layer reuse, separate from vector-only picture retention.
final class SceneLayerCache {
  SceneLayerCache(
    this.record,
    this.boundsFor, {
    this.pictureByteLimit = 16 * 1024 * 1024,
    this.rasterEstimateLimit = 64 * 1024 * 1024,
    this.layerLimit = 33,
  }) {
    if (pictureByteLimit < 0 || rasterEstimateLimit < 0 || layerLimit < 1) {
      throw ArgumentError('Invalid layer budget.');
    }
  }

  final ui.Picture Function(List<int>, Bounds2, double) record;
  final Bounds2 Function(int) boundsFor;
  final int pictureByteLimit;
  final int rasterEstimateLimit;
  final int layerLimit;
  static const activeLimit = 32;
  final _layers = <(int, int), _StaticRange>{};
  Set<int> _active = {};
  bool _activeOverflow = false;
  Bounds2? _viewport;
  double? _zoom;
  double? _dpr;
  bool _disposed = false;
  int bytes = 0;
  int peakBytes = 0;
  int rasterEstimate = 0;
  int peakRasterEstimate = 0;
  int builds = 0;
  int reuses = 0;
  int invalidations = 0;
  int clears = 0;
  int fallbacks = 0;
  int disposedRanges = 0;
  int engineSubmissions = 0;
  int? _firstPaintMicros;
  final _recordTimes = TimingSamples();

  Map<String, Object?> get statistics => {
    'layers': _layers.length,
    'layerLimit': layerLimit,
    'approximatePictureBytes': bytes,
    'peakApproximatePictureBytes': peakBytes,
    'pictureByteLimit': pictureByteLimit,
    'estimatedRasterExposureBytes': rasterEstimate,
    'peakEstimatedRasterExposureBytes': peakRasterEstimate,
    'rasterEstimateLimit': rasterEstimateLimit,
    'rasterEstimateAllocationFactor': 2,
    'activeCount': _active.length,
    'activeOverflow': _activeOverflow,
    'builds': builds,
    'reuses': reuses,
    'invalidations': invalidations,
    'clears': clears,
    'directFallbacks': fallbacks,
    'disposedRanges': disposedRanges,
    'engineSubmissions': engineSubmissions,
    'firstPaintRecordCpuMs': _firstPaintMicros == null
        ? null
        : _firstPaintMicros! / 1000,
    'recordCpu': _recordTimes.toJson(),
    'disposed': _disposed,
  };

  void setActiveIndices(Set<int> active) {
    if (_disposed) throw StateError('Layer cache disposed.');
    final overflow = active.length > activeLimit;
    final next = overflow ? <int>{} : Set<int>.of(active);
    if (overflow == _activeOverflow && setEquals(next, _active)) return;
    clear();
    _active = next;
    _activeOverflow = overflow;
  }

  void _remove((int, int) key) {
    final entry = _layers.remove(key);
    if (entry == null) return;
    bytes -= entry.bytes;
    // Detach before releasing our handle; PictureLayer alone owns its picture.
    entry.handle.layer?.remove();
    entry.handle.layer = null;
    disposedRanges++;
  }

  void clear() {
    for (final key in _layers.keys.toList()) {
      _remove(key);
    }
    rasterEstimate = 0;
    clears++;
    _firstPaintMicros = null;
  }

  void invalidate(Iterable<int> changed) {
    final indices = changed.where((i) => !_active.contains(i)).toList();
    for (final key in _layers.keys.toList()) {
      if (indices.any((i) => i >= key.$1 && i <= key.$2)) {
        _remove(key);
        invalidations++;
      }
    }
  }

  bool paint(
    PaintingContext context,
    ui.Offset offset,
    List<int> visible,
    Bounds2 viewport,
    double zoom,
    double devicePixelRatio, {
    int? movingIndex,
    required void Function(List<int>) paintDirect,
  }) {
    if (_disposed) throw StateError('Layer cache disposed.');
    if (!zoom.isFinite ||
        zoom <= 0 ||
        !devicePixelRatio.isFinite ||
        devicePixelRatio <= 0) {
      throw ArgumentError('Invalid layer scale.');
    }
    final screenWidth = viewport.width * zoom;
    final screenHeight = viewport.height * zoom;
    if (!screenWidth.isFinite || !screenHeight.isFinite) {
      throw ArgumentError('Nonfinite projected viewport.');
    }
    final active = movingIndex == null ? _active : {..._active, movingIndex};
    if (_activeOverflow ||
        active.length > activeLimit ||
        pictureByteLimit == 0 ||
        rasterEstimateLimit == 0) {
      clear();
      fallbacks++;
      return false;
    }
    for (var i = 1; i < visible.length; i++) {
      if (visible[i] <= visible[i - 1]) {
        clear();
        fallbacks++;
        return false;
      }
    }
    if (_viewport != viewport || _zoom != zoom || _dpr != devicePixelRatio) {
      clear();
      _viewport = viewport;
      _zoom = zoom;
      _dpr = devicePixelRatio;
    }
    final clock = Stopwatch()..start();
    final segments = <List<int>>[];
    for (var cursor = 0; cursor < visible.length;) {
      if (active.contains(visible[cursor])) {
        segments.add([visible[cursor++]]);
      } else {
        final start = cursor++;
        while (cursor < visible.length && !active.contains(visible[cursor])) {
          cursor++;
        }
        segments.add(visible.sublist(start, cursor));
      }
    }
    final staticRuns = segments
        .where((s) => !active.contains(s.first))
        .toList();
    // Full projected paint bounds, without intersecting the viewport, plus AA
    // margins and a 2x allowance. This is not a hard engine/GPU-memory cap.
    var exposure = 0;
    final paintBounds = <(int, int), ui.Rect>{};
    for (final indices in staticRuns) {
      var bounds = boundsFor(indices.first);
      for (final i in indices.skip(1)) {
        final next = boundsFor(i);
        bounds = Bounds2(
          math.min(bounds.left, next.left),
          math.min(bounds.top, next.top),
          math.max(bounds.right, next.right),
          math.max(bounds.bottom, next.bottom),
        );
      }
      final left = (bounds.left - viewport.left) * zoom;
      final top = (bounds.top - viewport.top) * zoom;
      final right = (bounds.right - viewport.left) * zoom;
      final bottom = (bounds.bottom - viewport.top) * zoom;
      // The recorded explicit viewport clip also bounds ink that exceeds an
      // element's authoring box (for example text). Never estimate below it.
      final width =
          math
              .max(
                (right - left) * devicePixelRatio,
                screenWidth * devicePixelRatio,
              )
              .ceilToDouble() +
          (4 * devicePixelRatio).ceilToDouble() +
          4;
      final height =
          math
              .max(
                (bottom - top) * devicePixelRatio,
                screenHeight * devicePixelRatio,
              )
              .ceilToDouble() +
          (4 * devicePixelRatio).ceilToDouble() +
          4;
      final estimate = width * height * 4 * 2;
      if (!estimate.isFinite ||
          estimate > rasterEstimateLimit ||
          bounds.width > 65536 ||
          bounds.height > 65536) {
        clear();
        fallbacks++;
        return false;
      }
      exposure += estimate.ceil();
      paintBounds[(indices.first, indices.last)] = ui.Rect.fromLTRB(
        left,
        top,
        right,
        bottom,
      ).inflate(2 / devicePixelRatio);
    }
    if (staticRuns.length > layerLimit || exposure > rasterEstimateLimit) {
      clear();
      fallbacks++;
      return false;
    }
    final keys = paintBounds.keys.toSet();
    for (final key in _layers.keys.toList()) {
      if (!keys.contains(key)) _remove(key);
    }
    rasterEstimate = exposure;
    peakRasterEstimate = math.max(peakRasterEstimate, exposure);
    final screen = ui.Rect.fromLTWH(
      0,
      0,
      viewport.width * zoom,
      viewport.height * zoom,
    );
    try {
      for (final indices in staticRuns) {
        final key = (indices.first, indices.last);
        var entry = _layers[key];
        if (entry != null && !listEquals(entry.indices, indices)) {
          _remove(key);
          entry = null;
        }
        if (entry == null) {
          final recording = Stopwatch()..start();
          final picture = record(indices, viewport, zoom);
          _recordTimes.add(recording.elapsedMicroseconds);
          final size = picture.approximateBytesUsed;
          if (bytes + size > pictureByteLimit) {
            picture.dispose();
            clear();
            fallbacks++;
            return false;
          }
          final leaf = PictureLayer(paintBounds[key]!)
            ..picture = picture
            ..isComplexHint = true;
          final clip = ClipRectLayer(
            clipRect: screen,
            clipBehavior: Clip.antiAlias,
          )..append(leaf);
          final root = _CountedOffsetLayer(() => engineSubmissions++)
            ..append(clip);
          entry = _StaticRange(LayerHandle<OffsetLayer>(root), indices, size);
          _layers[key] = entry;
          bytes += size;
          peakBytes = math.max(peakBytes, bytes);
          builds++;
        } else {
          reuses++;
        }
      }
    } catch (_) {
      clear();
      rethrow;
    }
    for (final indices in segments) {
      if (active.contains(indices.first)) {
        paintDirect(indices);
      } else {
        final root = _layers[(indices.first, indices.last)]!.handle.layer!;
        root.offset = offset;
        context.addLayer(root);
      }
    }
    _firstPaintMicros ??= clock.elapsedMicroseconds;
    return true;
  }

  void dispose() {
    if (_disposed) return;
    clear();
    _active.clear();
    _disposed = true;
  }
}

final class _StaticRange {
  _StaticRange(this.handle, this.indices, this.bytes);
  final LayerHandle<OffsetLayer> handle;
  final List<int> indices;
  final int bytes;
}

final class _CountedOffsetLayer extends OffsetLayer {
  _CountedOffsetLayer(this.onSubmit);
  final VoidCallback onSubmit;
  @override
  void addToScene(ui.SceneBuilder builder) {
    onSubmit();
    super.addToScene(builder);
  }
}
