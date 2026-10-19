import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../geometry/geometry.dart';
import 'frame_samples.dart';

/// Ordered vector reuse only; this does not create independently cached rasters.
final class ScenePictureCache {
  ScenePictureCache(
    this.record,
    this.boundsFor, {
    this.byteLimit = 16 * 1024 * 1024,
    this.pictureLimit = 128,
  }) {
    if (byteLimit < 0 || pictureLimit < 1) {
      throw ArgumentError('Invalid picture budget');
    }
  }

  final ui.Picture Function(List<int> indices, Point2 origin) record;
  final Bounds2 Function(int index) boundsFor;
  final int byteLimit;
  final int pictureLimit;
  static const rangeSize = 256;
  static const activeLimit = 32;
  static const maximumLocalSpan = 65536.0;
  final _pictures = <(int, int), _PictureRange>{};
  Set<int> _active = {};
  bool _activeOverflow = false;
  bool _disposed = false;
  int bytes = 0;
  int peakBytes = 0;
  int builds = 0;
  int reuses = 0;
  int recordedEntries = 0;
  int invalidations = 0;
  int evictions = 0;
  int fallbacks = 0;
  int clears = 0;
  int disposedPictures = 0;
  int? _firstPaintMicros;
  final _recordTimes = TimingSamples();

  Map<String, Object?> get statistics => {
    'approximateBytes': bytes,
    'peakApproximateBytes': peakBytes,
    'limitApproximateBytes': byteLimit,
    'pictures': _pictures.length,
    'pictureLimit': pictureLimit,
    'rangeSize': rangeSize,
    'activeCount': _active.length,
    'activeOverflow': _activeOverflow,
    'builds': builds,
    'reuses': reuses,
    'recordedEntries': recordedEntries,
    'invalidations': invalidations,
    'evictions': evictions,
    'directFallbacks': fallbacks,
    'clears': clears,
    'disposedPictures': disposedPictures,
    'firstPaintRecordCpuMs': _firstPaintMicros == null
        ? null
        : _firstPaintMicros! / 1000,
    'recordCpu': _recordTimes.toJson(),
    'disposed': _disposed,
  };

  void setActiveIndices(Set<int> active) {
    if (_disposed) throw StateError('Picture cache disposed');
    final overflow = active.length > activeLimit;
    final next = overflow ? <int>{} : Set<int>.of(active);
    if (_activeOverflow == overflow && setEquals(_active, next)) return;
    clear();
    _active = next;
    _activeOverflow = overflow;
  }

  void clear() {
    for (final key in _pictures.keys.toList()) {
      _remove(key);
    }
    clears++;
    _firstPaintMicros = null;
  }

  void _remove((int, int) key) {
    final entry = _pictures.remove(key);
    if (entry == null) return;
    bytes -= entry.bytes;
    entry.picture.dispose();
    disposedPictures++;
  }

  void invalidate(Iterable<int> changed) {
    final affected = changed.where((i) => !_active.contains(i)).toList();
    if (affected.isEmpty) return;
    final dirty = _pictures.keys
        .where((key) => affected.any((i) => i >= key.$1 && i < key.$2))
        .toList();
    for (final key in dirty) {
      _remove(key);
      invalidations++;
    }
  }

  bool paint(
    ui.Canvas canvas,
    List<int> visible,
    Point2 worldOrigin, {
    int? movingIndex,
    required void Function(List<int>) paintDirect,
  }) {
    if (_disposed) throw StateError('Picture cache disposed');
    if (_activeOverflow ||
        (_active.length == activeLimit &&
            movingIndex != null &&
            !_active.contains(movingIndex))) {
      fallbacks++;
      return false;
    }
    for (var i = 1; i < visible.length; i++) {
      if (visible[i] <= visible[i - 1]) {
        fallbacks++;
        return false;
      }
    }
    final clock = Stopwatch()..start();
    final active = movingIndex == null ? _active : {..._active, movingIndex};
    for (var cursor = 0; cursor < visible.length;) {
      final index = visible[cursor];
      if (active.contains(index)) {
        paintDirect([index]);
        cursor++;
        continue;
      }
      var start = index ~/ rangeSize * rangeSize;
      var end = start + rangeSize;
      for (final i in active) {
        if (i < index && i >= start) start = i + 1;
        if (i > index && i < end) end = i;
      }
      final begin = cursor++;
      while (cursor < visible.length && visible[cursor] < end) {
        cursor++;
      }
      final indices = visible.sublist(begin, cursor);
      final key = (start, end);
      var entry = _pictures.remove(key);
      if (entry != null && !listEquals(entry.indices, indices)) {
        _pictures[key] = entry;
        _remove(key);
        entry = null;
      }
      if (entry == null) {
        var bounds = boundsFor(indices.first);
        for (final i in indices.skip(1)) {
          final b = boundsFor(i);
          bounds = Bounds2(
            math.min(bounds.left, b.left),
            math.min(bounds.top, b.top),
            math.max(bounds.right, b.right),
            math.max(bounds.bottom, b.bottom),
          );
        }
        if (bounds.width > maximumLocalSpan ||
            bounds.height > maximumLocalSpan ||
            byteLimit == 0) {
          fallbacks++;
          paintDirect(indices);
          continue;
        }
        final origin = bounds.center;
        final build = Stopwatch()..start();
        final picture = record(indices, origin);
        _recordTimes.add(build.elapsedMicroseconds);
        builds++;
        recordedEntries += indices.length;
        final size = picture.approximateBytesUsed;
        if (size > byteLimit) {
          picture.dispose();
          disposedPictures++;
          fallbacks++;
          paintDirect(indices);
          continue;
        }
        while (_pictures.isNotEmpty &&
            (bytes + size > byteLimit || _pictures.length >= pictureLimit)) {
          _remove(_pictures.keys.first);
          evictions++;
        }
        entry = _PictureRange(picture, indices, origin, size);
        bytes += size;
        peakBytes = math.max(peakBytes, bytes);
      } else {
        reuses++;
      }
      _pictures[key] = entry;
      canvas.save();
      canvas.translate(
        entry.origin.x - worldOrigin.x,
        entry.origin.y - worldOrigin.y,
      );
      canvas.drawPicture(entry.picture);
      canvas.restore();
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

final class _PictureRange {
  const _PictureRange(this.picture, this.indices, this.origin, this.bytes);
  final ui.Picture picture;
  final List<int> indices;
  final Point2 origin;
  final int bytes;
}
