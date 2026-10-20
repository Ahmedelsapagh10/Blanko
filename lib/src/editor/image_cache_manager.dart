import 'dart:async';
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

  final _cache = <String, _CachedImage>{};
  final _pending = <String, Future<ui.Image?>>{};
  int _currentBytes = 0;
  int _generation = 0;
  bool _disposed = false;

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
  }) {
    if (_disposed) return Future.value(null);
    final existing = get(assetId);
    if (existing != null) return Future.value(existing);

    final inFlight = _pending[assetId];
    if (inFlight != null) return inFlight;

    final requestGen = _generation;
    final future = _decodeAsync(
      assetId,
      byteSource,
      requestGen,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    _pending[assetId] = future;
    return future;
  }

  Future<ui.Image?> _decodeAsync(
    String assetId,
    Future<Uint8List?> Function() byteSource,
    int requestGen, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    try {
      final bytes = await byteSource();
      if (bytes == null || bytes.isEmpty) return null;
      if (_disposed || requestGen != _generation) return null;

      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (_disposed || requestGen != _generation) {
        descriptor.dispose();
        buffer.dispose();
        return null;
      }

      // Resolution-aware target constraints (max 2048 in any dimension for safety)
      int? tw = targetWidth;
      int? th = targetHeight;
      const maxDim = 2048;
      if (descriptor.width > maxDim || descriptor.height > maxDim) {
        if (descriptor.width >= descriptor.height) {
          tw = maxDim;
          th = (descriptor.height * maxDim / descriptor.width).round();
        } else {
          th = maxDim;
          tw = (descriptor.width * maxDim / descriptor.height).round();
        }
      }

      final codec = await descriptor.instantiateCodec(
        targetWidth: tw,
        targetHeight: th,
      );
      descriptor.dispose();
      buffer.dispose();

      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();

      if (_disposed || requestGen != _generation) {
        image.dispose();
        return null;
      }

      final imageBytes = image.width * image.height * 4;
      _evictToFit(imageBytes);

      _cache[assetId] = _CachedImage(
        image: image,
        bytes: imageBytes,
        lastAccess: DateTime.now().microsecondsSinceEpoch,
      );
      _currentBytes += imageBytes;
      return image;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(assetId);
    }
  }

  void _evictToFit(int newBytes) {
    while (_cache.isNotEmpty &&
        (_currentBytes + newBytes > maxBytes || _cache.length >= maxEntries)) {
      String? oldestKey;
      var oldestAccess = _cache.values.first.lastAccess;
      for (final entry in _cache.entries) {
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
        break;
      }
    }
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
    _currentBytes = 0;
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
