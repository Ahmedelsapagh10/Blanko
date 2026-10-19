import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../geometry/geometry.dart';
import 'frame_samples.dart';

typedef TileKey = (int, int, int);
typedef TileRepair =
    ui.Picture Function(
      Bounds2 bounds,
      double scale,
      ui.Image base,
      List<Bounds2> damage,
    );

/// Disposable raster reuse only. Geometry and paint order stay in the renderer.
final class SceneTileCache {
  SceneTileCache(
    this.record, {
    this.byteLimit = 64 * 1024 * 1024,
    this.recovery = false,
    this.repair,
  }) : assert(repair == null || recovery);

  final bool recovery;
  final TileRepair? repair;
  int get tileSide => side;
  int get tileBytes => (tileSide + 2) * (tileSide + 2) * 4;
  Bounds2 _boundsFor(TileKey key) => boundsFor(key, tileSide: tileSide);

  final ui.Picture Function(Bounds2 bounds, double scale) record;
  final int byteLimit;
  static const side = 512;
  static const imageBytes = (side + 2) * (side + 2) * 4;
  final changed = ValueNotifier<int>(0);
  final _images = <TileKey, ui.Image>{};
  final _damage = <TileKey, List<Bounds2>>{};
  Set<TileKey> _wanted = {};
  final _failed = <TileKey>{};
  Future<void>? _pending;
  bool _disposed = false;
  int _epoch = 0;
  TileKey? _inFlight;
  int builds = 0;
  int evictions = 0;
  int invalidations = 0;
  int discarded = 0;
  int errors = 0;
  int paintHits = 0;
  int paintMisses = 0;
  int mixedPaints = 0;
  int liveRegions = 0;
  int peakBytes = 0;
  int repairs = 0;
  int repairPixels = 0;
  int _pinnedHandles = 0;
  int buildMicros = 0;
  final _recordTimes = TimingSamples();
  final _imageWaitTimes = TimingSamples();
  final _buildTimes = TimingSamples();
  int _maxBuildMicros = 0;
  int get bytes => _images.length * tileBytes;
  int get handles => _images.length;
  Map<String, Object?> get statistics => {
    'bytes': bytes,
    'recovery': recovery,
    'dirtyRepair': repair != null,
    'repairs': repairs,
    'repairPixels': repairPixels,
    'dirtyEntries': _damage.length,
    'pinnedHandles': _pinnedHandles,
    'tileSide': tileSide,
    'mixedPaints': mixedPaints,
    'liveRegions': liveRegions,
    'limitBytes': byteLimit,
    'peakBytes': peakBytes,
    'entries': handles,
    'builds': builds,
    'evictions': evictions,
    'invalidations': invalidations,
    'discarded': discarded,
    'errors': errors,
    'paintHits': paintHits,
    'paintMisses': paintMisses,
    'buildWallMs': buildMicros / 1000,
    'recordCpu': _recordTimes.toJson(),
    'imageAwaitWall': _imageWaitTimes.toJson(),
    'buildWall': _buildTimes.toJson(),
    'maxBuildMs': _maxBuildMicros / 1000,
    'pending': _pending != null,
  };

  static int bucket(double pixelScale) {
    if (!pixelScale.isFinite || pixelScale <= 0) {
      throw ArgumentError.value(pixelScale, 'pixelScale');
    }
    return (math.log(pixelScale) / math.ln2).ceil().clamp(-6, 8);
  }

  static Bounds2 boundsFor(TileKey key, {int tileSide = side}) {
    final width = tileSide / math.pow(2, key.$1);
    return Bounds2(
      key.$2 * width,
      key.$3 * width,
      (key.$2 + 1) * width,
      (key.$3 + 1) * width,
    );
  }

  List<TileKey> keysFor(Bounds2 view, double pixelScale) {
    final level = bucket(pixelScale);
    if (pixelScale > 256) return const [];
    final width = tileSide / math.pow(2, level);
    final left = (view.left / width).floor();
    final top = (view.top / width).floor();
    final right = (view.right / width).ceil() - 1;
    final bottom = (view.bottom / width).ceil() - 1;
    if ((right - left + 1) * (bottom - top + 1) * tileBytes > byteLimit) {
      return const [];
    }
    return [
      for (var x = left; x <= right; x++)
        for (var y = top; y <= bottom; y++) (level, x, y),
    ];
  }

  Future<void> prepare(Bounds2 view, double pixelScale) {
    if (_disposed) return Future.value();
    _wanted = keysFor(view, pixelScale).toSet();
    for (final key in _wanted) {
      final image = _images.remove(key);
      if (image != null) _images[key] = image;
    }
    return _pending ??= _pump().whenComplete(() {
      _pending = null;
    });
  }

  Future<void> _pump() async {
    // Yield before recording, so cache work never mutates state inside paint.
    await Future<void>.value();
    while (!_disposed) {
      final missing = _wanted.where(
        (key) =>
            (!_images.containsKey(key) || _damage.containsKey(key)) &&
            !_failed.contains(key),
      );
      if (missing.isEmpty) return;
      final key = missing.first;
      _inFlight = key;
      final epoch = _epoch;
      final clock = Stopwatch()..start();
      ui.Picture? picture;
      ui.Image? image;
      ui.Image? base;
      try {
        final damage = _damage[key];
        final scale = math.pow(2, key.$1).toDouble();
        // Pin a handle: invalidation, eviction or disposal can release the
        // resident handle while the engine still consumes this picture.
        if (damage != null) {
          base = _images[key]?.clone();
          if (base != null) _pinnedHandles++;
        }
        picture = base == null
            ? record(_boundsFor(key), scale)
            : repair!(_boundsFor(key), scale, base, damage!);
        _recordTimes.add(clock.elapsedMicroseconds);
        final wait = Stopwatch()..start();
        image = await picture.toImage(tileSide + 2, tileSide + 2);
        _imageWaitTimes.add(wait.elapsedMicroseconds);
        if (_disposed ||
            epoch != _epoch ||
            (!_wanted.contains(key) &&
                bytes + tileBytes > byteLimit &&
                _images.keys.every(_wanted.contains))) {
          image.dispose();
          discarded++;
        } else {
          while (bytes + (_images.containsKey(key) ? 0 : tileBytes) >
                  byteLimit &&
              _images.isNotEmpty) {
            final victim = _images.keys.firstWhere(
              (k) => !_wanted.contains(k),
              orElse: () => _images.keys.first,
            );
            _images.remove(victim)!.dispose();
            _damage.remove(victim);
            evictions++;
          }
          _images.remove(key)?.dispose();
          _images[key] = image;
          if (base != null) {
            repairs++;
            for (final bounds in damage!) {
              repairPixels += (bounds.width * bounds.height * scale * scale)
                  .ceil();
            }
          }
          _damage.remove(key);
          builds++;
          peakBytes = math.max(peakBytes, bytes);
          changed.value++;
        }
      } catch (_) {
        image?.dispose();
        errors++;
        if (!_disposed) {
          if (_failed.length >= 64) _failed.clear();
          _failed.add(key);
        }
      } finally {
        _inFlight = null;
        picture?.dispose();
        base?.dispose();
        if (base != null) _pinnedHandles--;
        final duration = clock.elapsedMicroseconds;
        buildMicros += duration;
        _buildTimes.add(duration);
        _maxBuildMicros = math.max(_maxBuildMicros, duration);
      }
      await Future<void>.value();
    }
  }

  bool paint(
    ui.Canvas canvas,
    Bounds2 view,
    double pixelScale,
    Point2 origin, {
    void Function(List<Bounds2> bounds)? paintMissing,
  }) {
    if (_disposed) return false;
    final keys = keysFor(view, pixelScale);
    if (keys.isEmpty) {
      paintMisses++;
      return false;
    }
    final missing = keys.any(
      (key) => !_images.containsKey(key) || _damage.containsKey(key),
    );
    if (missing) {
      paintMisses++;
      unawaited(prepare(view, pixelScale));
      if (!recovery || paintMissing == null) return false;
    } else {
      paintHits++;
    }
    _wanted = keys.toSet();
    final missingBounds = [
      for (final key in keys)
        if (!_images.containsKey(key))
          _boundsFor(key)
        else
          ..._visibleDamage(key),
    ];
    if (keys.every((key) => !_images.containsKey(key))) return false;
    if (missingBounds.isNotEmpty) mixedPaints++;
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.low;
    for (final key in keys) {
      final image = _images.remove(key);
      if (image == null) continue;
      final bounds = _boundsFor(key);
      final scale = math.pow(2, key.$1).toDouble();
      canvas.save();
      // Clip the gutter to avoid painting translucent edges twice.
      canvas.clipRect(
        ui.Rect.fromLTRB(
          bounds.left - origin.x,
          bounds.top - origin.y,
          bounds.right - origin.x,
          bounds.bottom - origin.y,
        ),
        doAntiAlias: !recovery,
      );
      if (_damage[key] case final damage?) {
        for (final area in damage) {
          canvas.clipRect(
            ui.Rect.fromLTRB(
              area.left - origin.x,
              area.top - origin.y,
              area.right - origin.x,
              area.bottom - origin.y,
            ),
            clipOp: ui.ClipOp.difference,
            doAntiAlias: false,
          );
        }
      }
      _images[key] = image;
      canvas.translate(
        bounds.left - origin.x - 1 / scale,
        bounds.top - origin.y - 1 / scale,
      );
      canvas.scale(1 / scale);
      canvas.drawImage(image, ui.Offset.zero, paint);
      canvas.restore();
    }
    if (missingBounds.isNotEmpty) {
      liveRegions += missingBounds.length;
      final clip = ui.Path();
      for (final bounds in missingBounds) {
        clip.addRect(
          ui.Rect.fromLTRB(
            bounds.left - origin.x,
            bounds.top - origin.y,
            bounds.right - origin.x,
            bounds.bottom - origin.y,
          ),
        );
      }
      canvas.save();
      canvas.clipPath(clip, doAntiAlias: false);
      paintMissing!(missingBounds);
      canvas.restore();
    }
    return true;
  }

  Iterable<Bounds2> _visibleDamage(TileKey key) sync* {
    final tile = _boundsFor(key);
    for (final area in _damage[key] ?? const <Bounds2>[]) {
      final left = math.max(tile.left, area.left);
      final top = math.max(tile.top, area.top);
      final right = math.min(tile.right, area.right);
      final bottom = math.min(tile.bottom, area.bottom);
      if (left < right && top < bottom) {
        yield Bounds2(left, top, right, bottom);
      }
    }
  }

  void invalidate(Iterable<Bounds2> affected) {
    if (_disposed) return;
    final areas = affected.toList();
    final pending = _inFlight;
    if (pending != null &&
        areas.any(
          _boundsFor(pending)
              .inflate((repair == null ? 1 : 2) / math.pow(2, pending.$1))
              .intersects,
        )) {
      _epoch++;
    }
    final dirty = _images.keys
        .where(
          (key) => areas.any(
            _boundsFor(key)
                .inflate((repair == null ? 1 : 2) / math.pow(2, key.$1))
                .intersects,
          ),
        )
        .toList();
    for (final key in dirty) {
      if (repair == null) {
        _images.remove(key)!.dispose();
      } else {
        final scale = math.pow(2, key.$1).toDouble();
        final tile = _boundsFor(key).inflate(1 / scale);
        final damage = [...?_damage[key]];
        for (final area in areas.where(tile.inflate(1 / scale).intersects)) {
          // Expand for antialiasing and snap outwards in tile pixel space.
          // Computing relative to the tile avoids float precision loss at 1e9.
          final padded = area.inflate(2 / scale);
          var added = Bounds2(
            tile.left +
                math.max(0, ((padded.left - tile.left) * scale).floor()) /
                    scale,
            tile.top +
                math.max(0, ((padded.top - tile.top) * scale).floor()) / scale,
            tile.left +
                math.min(
                      tileSide + 2,
                      ((padded.right - tile.left) * scale).ceil(),
                    ) /
                    scale,
            tile.top +
                math.min(
                      tileSide + 2,
                      ((padded.bottom - tile.top) * scale).ceil(),
                    ) /
                    scale,
          );
          if (added.width == 0 || added.height == 0) continue;
          // Coalesce overlaps rather than using even-odd holes, which would
          // accidentally restore stale pixels where damage overlaps.
          for (var i = 0; i < damage.length;) {
            final other = damage[i];
            if (!added.intersects(other)) {
              i++;
              continue;
            }
            added = Bounds2(
              math.min(added.left, other.left),
              math.min(added.top, other.top),
              math.max(added.right, other.right),
              math.max(added.bottom, other.bottom),
            );
            damage.removeAt(i);
            i = 0;
          }
          damage.add(added);
        }
        // Fragmented or almost-full damage uses the original bounded fallback.
        final area = damage.fold<double>(
          0,
          (sum, b) => sum + b.width * b.height,
        );
        if (damage.length > 16 || area >= tile.width * tile.height * .75) {
          _images.remove(key)!.dispose();
          _damage.remove(key);
        } else if (damage.isNotEmpty) {
          _damage[key] = damage;
        }
      }
      invalidations++;
    }
    _failed.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _wanted.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _damage.clear();
    _failed.clear();
    changed.dispose();
  }
}
