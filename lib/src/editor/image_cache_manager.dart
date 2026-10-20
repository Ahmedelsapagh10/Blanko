import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Bounded, resolution-aware cache for decoded [ui.Image] assets.
///
/// Prevents memory leaks by capping decoded pixel bytes, evicting least-recently
/// used images, and safely discarding stale in-flight asynchronous decodes when
/// boards switch or elements are disposed.
final class ImageCacheManager {
  ImageCacheManager({this.maxBytes = 96 * 1024 * 1024, this.maxEntries = 40});

  final int maxBytes;
  final int maxEntries;

  Set<String> _visibleAssets = {};
  Object? _viewport;
  static const capacityError =
      'Decoded image cache is full. Pan or zoom to reduce visible images, then retry.';

  final _cache = <String, _CachedImage>{};
  final _requests = <String, Object>{};
  final _pending = <String, Future<ui.Image?>>{};
  int _currentBytes = 0;
  int _generation = 0;
  bool _disposed = false;

  final errors = <String, String>{};

  int get currentBytes => _currentBytes;
  int get cachedCount => _cache.length;
  bool get isDisposed => _disposed;

  /// Retrieves an already decoded image if present, marking it as recently used.
  ui.Image? get(String assetId) {
    if (_disposed) return null;
    final cached = _cache[assetId];
    if (cached != null) {
      cached.lastAccess = DateTime.now().microsecondsSinceEpoch;
      return cached.image;
    }
    return null;
  }

  /// Loads, decodes and caches an image from raw bytes with resolution capping.
  ///
  /// If the image is already cached or currently decoding, reuses the instance.
  /// If [generation] doesn't match the current manager generation after decode,
  /// the decoded image is immediately disposed to prevent stale publications.
  Future<ui.Image?> load(
    String assetId,
    Future<Uint8List?> Function() byteSource, {
    int? targetWidth,
    int? targetHeight,
    void Function(int width, int height)? onDimensions,
  }) {
    if (_disposed) return Future.value(null);
    final existing = get(assetId);
    if (existing != null) return Future.value(existing);

    final inFlight = _pending[assetId];
    if (inFlight != null) return inFlight;

    errors.remove(assetId);
    final requestGen = _generation;
    final request = Object();
    _requests[assetId] = request;
    final future = _decodeAsync(
      assetId,
      byteSource,
      requestGen,
      request,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      onDimensions: onDimensions,
    );
    _pending[assetId] = future;
    return future;
  }

  Future<ui.Image?> _decodeAsync(
    String assetId,
    Future<Uint8List?> Function() byteSource,
    int requestGen,
    Object request, {
    int? targetWidth,
    int? targetHeight,
    void Function(int width, int height)? onDimensions,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.Codec? codec;
    try {
      final bytes = await byteSource();
      if (_disposed ||
          requestGen != _generation ||
          !identical(_requests[assetId], request)) {
        return null;
      }
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Original image asset is missing.');
      }
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final source = buffer;
      buffer = null;
      codec = await ui.instantiateImageCodecWithSize(
        source,
        getTargetSize: (width, height) {
          onDimensions?.call(width, height);
          final requestedScale = [
            1.0,
            2048 / width,
            2048 / height,
            if (targetWidth != null) targetWidth / width,
            if (targetHeight != null) targetHeight / height,
            math.sqrt(maxBytes / (width * height * 4)),
          ].reduce(math.min);
          return ui.TargetImageSize(
            width: (width * requestedScale).floor().clamp(1, 2048),
            height: (height * requestedScale).floor().clamp(1, 2048),
          );
        },
      );
      // instantiateImageCodecWithSize owns and disposes the immutable buffer.
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (_disposed ||
          requestGen != _generation ||
          !identical(_requests[assetId], request)) {
        image.dispose();
        return null;
      }
      final imageBytes = image.width * image.height * 4;
      if (imageBytes > maxBytes) {
        image.dispose();
        throw StateError('Image exceeds decoded memory budget.');
      }
      if (!_evictToFit(imageBytes)) {
        image.dispose();
        throw StateError(capacityError);
      }
      _cache[assetId] = _CachedImage(
        image: image,
        bytes: imageBytes,
        lastAccess: DateTime.now().microsecondsSinceEpoch,
      );
      _currentBytes += imageBytes;
      return image;
    } catch (error) {
      if (!_disposed &&
          requestGen == _generation &&
          identical(_requests[assetId], request)) {
        errors[assetId] = error.toString();
      }
      return null;
    } finally {
      codec?.dispose();
      buffer?.dispose();
      if (identical(_requests[assetId], request)) {
        _pending.remove(assetId);
        _requests.remove(assetId);
      }
    }
  }

  void retainOnly(Set<String> assetIds) {
    for (final id in _cache.keys.toList()) {
      if (assetIds.contains(id)) continue;
      final cached = _cache.remove(id)!;
      _currentBytes -= cached.bytes;
      cached.image.dispose();
    }
    for (final id in _requests.keys.toList()) {
      if (assetIds.contains(id)) continue;
      _requests.remove(id);
      _pending.remove(id);
    }
    errors.removeWhere((id, _) => !assetIds.contains(id));
  }

  void updateVisibleAssets(Set<String> assets, Object viewport) {
    if (_viewport != viewport ||
        assets.length != _visibleAssets.length ||
        !assets.containsAll(_visibleAssets)) {
      errors.removeWhere((_, error) => error.contains(capacityError));
    }
    _viewport = viewport;
    _visibleAssets = assets;
  }

  bool _evictToFit(int newBytes) {
    while (_cache.isNotEmpty &&
        (_currentBytes + newBytes > maxBytes || _cache.length >= maxEntries)) {
      String? oldestKey;
      var oldestAccess = _cache.values.first.lastAccess;
      for (final entry in _cache.entries) {
        if (_visibleAssets.contains(entry.key)) continue;
        if (oldestKey == null || entry.value.lastAccess < oldestAccess) {
          oldestAccess = entry.value.lastAccess;
          oldestKey = entry.key;
        }
      }
      if (oldestKey != null) {
        final removed = _cache.remove(oldestKey);
        if (removed != null) {
          _currentBytes -= removed.bytes;
          removed.image.dispose();
        }
      } else {
        return false;
      }
    }
    return true;
  }

  /// Increments the generation and clears the cache, safely disposing all images.
  ///
  /// Call this when switching active boards to invalidate in-flight async decodes.
  void clear() {
    _generation++;
    for (final cached in _cache.values) {
      cached.image.dispose();
    }
    _cache.clear();
    _pending.clear();
    _requests.clear();
    errors.clear();
    _currentBytes = 0;
    _visibleAssets = {};
    _viewport = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
  }
}

final class _CachedImage {
  _CachedImage({
    required this.image,
    required this.bytes,
    required this.lastAccess,
  });

  final ui.Image image;
  final int bytes;
  int lastAccess;
}
