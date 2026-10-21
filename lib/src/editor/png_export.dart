import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../document/document.dart';
import '../document/document_geometry.dart';
import '../document/element.dart';
import '../geometry/geometry.dart';
import '../persistence/board_store.dart';
import 'artwork_painter.dart';
import 'editor_scene.dart';
import 'editor_text.dart';

final class PngExportCancelled implements Exception {
  const PngExportCancelled();
  @override
  String toString() => 'PNG export cancelled.';
}

/// An oriented source region. Frame views remove rotation/translation only;
/// inverse affine scaling would distort artwork inside a scaled/sheared frame.
({Bounds2 bounds, Transform2 worldToRegion, List<Point2>? framePolygon})
resolvePngExportRegion({
  required BoardDocument document,
  required Bounds2 bounds,
  ElementId? frameId,
}) {
  if (frameId == null) {
    return (
      bounds: bounds,
      worldToRegion: Transform2.identity,
      framePolygon: null,
    );
  }
  final content = document.byId[frameId]?.content;
  if (content is! ExportFrameElementContent) {
    throw ArgumentError('Select an Export Frame to export a frame region.');
  }
  final world = DocumentGeometry(document).worldTransformOf(frameId);
  final view =
      Transform2.rotation(-math.atan2(world.b, world.a)) *
      Transform2.translation(-world.tx, -world.ty);
  final frameToRegion = view * world;
  final b = content.bounds;
  return (
    bounds: frameToRegion.mapBounds(b),
    worldToRegion: view,
    framePolygon: [
      Point2(b.left, b.top),
      Point2(b.right, b.top),
      Point2(b.right, b.bottom),
      Point2(b.left, b.bottom),
    ].map(frameToRegion.apply).toList(),
  );
}

/// Renders a committed snapshot, independently of editor handles and caches.
/// Limits account for output and retained decoded images, not GPU/codec peaks.
Future<Uint8List> renderBoardPng({
  required BoardDocument document,
  required BoardStore? store,
  required Bounds2 bounds,
  required int width,
  required int height,
  ElementId? frameId,
  int? backgroundColor,
  bool Function()? isCancelled,
}) async {
  if (width < 1 ||
      height < 1 ||
      width > 8192 ||
      height > 8192 ||
      width * height > 16000000) {
    throw ArgumentError(
      'PNG size must be 1–8192 per side and at most 16 megapixels.',
    );
  }
  if (bounds.width <= 0 || bounds.height <= 0) {
    throw ArgumentError('Export bounds must have positive dimensions.');
  }
  if (backgroundColor != null &&
      (backgroundColor < 0 || backgroundColor > 0xffffffff)) {
    throw ArgumentError('Invalid PNG background color.');
  }
  void checkCancelled() {
    if (isCancelled?.call() ?? false) {
      throw const PngExportCancelled();
    }
  }

  checkCancelled();
  final geometry = DocumentGeometry(document);
  final scene = EditorScene(document);
  final source = resolvePngExportRegion(
    document: document,
    bounds: bounds,
    frameId: frameId,
  );
  final region = source.bounds;
  final worldToRegion = source.worldToRegion;
  if (region.width <= 0 || region.height <= 0) {
    throw ArgumentError('Export bounds must have positive dimensions.');
  }
  final worldBounds = worldToRegion.inverse().mapBounds(region);
  final candidates = scene.visible(worldBounds);
  final images = <String, ui.Image>{};
  final layouts = <ElementId, TextPainter>{};
  ui.Picture? picture;
  ui.Image? output;
  ui.PictureRecorder? recorder;
  var decodedBytes = 0;
  const maxDecodedBytes = 96 * 1024 * 1024;
  try {
    await ensureEditorFonts();
    checkCancelled();
    for (final element in candidates) {
      final content = element.content;
      if (content is TextElementContent ||
          content is StickyNoteElementContent) {
        layouts[element.id] = layoutElementText(content);
      }
      if (content is! ImageElementContent ||
          images.containsKey(content.assetId)) {
        continue;
      }
      if (store == null) {
        throw StateError('Original image storage is unavailable.');
      }
      final reference = document.assets
          ?.where((asset) => asset.id == content.assetId)
          .firstOrNull;
      if (reference?.pixelWidth != null &&
          reference!.pixelWidth! * reference.pixelHeight! * 4 >
              maxDecodedBytes - decodedBytes) {
        throw StateError(
          'Images exceed the 96 MiB export budget. Export a smaller region.',
        );
      }
      final bytes = await store.readAsset(content.assetId);
      checkCancelled();
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'Original image ${content.assetId} is missing. Retry after restoring it.',
        );
      }
      if (bytes.length > 64 * 1024 * 1024) {
        throw StateError('Original image exceeds the 64 MiB export limit.');
      }
      ui.Codec? codec;
      ui.ImmutableBuffer? buffer;
      ui.ImageDescriptor? descriptor;
      try {
        // Web's engine bridge requires a native typed array, while imported
        // project originals can intentionally expose an unmodifiable view.
        buffer = await ui.ImmutableBuffer.fromUint8List(
          kIsWeb ? Uint8List.fromList(bytes) : bytes,
        );
        checkCancelled();
        void checkDimensions(int w, int h) {
          if (w * h * 4 > maxDecodedBytes - decodedBytes) {
            throw StateError(
              'Images exceed the 96 MiB export budget. Export a smaller region.',
            );
          }
        }

        if (kIsWeb) {
          // The Web helper owns the buffer; encoded descriptors are unsupported.
          final source = buffer;
          buffer = null;
          codec = await ui.instantiateImageCodecWithSize(
            source,
            getTargetSize: (w, h) {
              checkDimensions(w, h);
              return ui.TargetImageSize(width: w, height: h);
            },
          );
        } else {
          // Explicit ownership also covers corrupt encoded-header failures.
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          checkDimensions(descriptor.width, descriptor.height);
          codec = await descriptor.instantiateCodec();
        }
        checkCancelled();
        final frame = await codec.getNextFrame();
        var image = frame.image;
        if (kIsWeb) {
          // Browser-decoded VideoFrame textures can draw transparently on
          // CanvasKit's independent picture-to-image surface. A CPU-backed
          // image keeps the original pixels usable by that offscreen surface.
          final decoded = image;
          try {
            image = await _rasterCopy(decoded);
          } finally {
            decoded.dispose();
          }
        }
        final imageBytes = image.width * image.height * 4;
        if (imageBytes > maxDecodedBytes - decodedBytes) {
          image.dispose();
          throw StateError('Images exceed the 96 MiB export budget.');
        }
        images[content.assetId] = image;
        decodedBytes += imageBytes;
        checkCancelled();
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer?.dispose();
      }
    }
    recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    if (backgroundColor != null) {
      canvas.drawColor(Color(backgroundColor), BlendMode.src);
    }
    // Fit uses a single pixel/world scale. Letterboxing belongs to the output
    // background, never to neighboring world artwork outside the source region.
    final scale = math.min(width / region.width, height / region.height);
    canvas.translate(
      (width - region.width * scale) / 2,
      (height - region.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-region.left, -region.top);
    canvas.clipRect(artworkRect(region));
    if (source.framePolygon case final corners?) {
      canvas.clipPath(
        Path()..addPolygon([
          for (final point in corners) Offset(point.x, point.y),
        ], true),
      );
    }
    canvas.transform(_matrix(worldToRegion));
    final alpha = <ElementId, double>{};
    for (final element in document.preorder) {
      alpha[element.id] = element.opacity * (alpha[element.parentId] ?? 1);
    }
    for (final element in candidates) {
      checkCancelled();
      if (element.content.canOwnChildren ||
          element.content is ExportFrameElementContent) {
        continue;
      }
      canvas.save();
      var parent = document.byId[element.parentId];
      while (parent != null) {
        final content = parent.content;
        if (content is ContainerFrameElementContent) {
          final parentWorld = geometry.worldTransformOf(parent.id);
          canvas.transform(_matrix(parentWorld));
          canvas.clipRect(artworkRect(content.bounds));
          canvas.transform(_matrix(parentWorld.inverse()));
        }
        parent = document.byId[parent.parentId];
      }
      canvas.transform(_matrix(geometry.worldTransformOf(element.id)));
      final content = element.content;
      paintElementArtwork(
        canvas,
        element,
        textLayout: layouts[element.id],
        image: content is ImageElementContent ? images[content.assetId] : null,
        opacity: alpha[element.id],
      );
      canvas.restore();
    }
    picture = recorder.endRecording();
    recorder = null;
    output = await picture.toImage(width, height);
    checkCancelled();
    final png = await output.toByteData(format: ui.ImageByteFormat.png);
    checkCancelled();
    if (png == null) throw StateError('The renderer could not encode the PNG.');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    if (recorder != null && recorder.isRecording) {
      recorder.endRecording().dispose();
    }
    output?.dispose();
    picture?.dispose();
    for (final image in images.values) {
      image.dispose();
    }
    for (final layout in layouts.values) {
      layout.dispose();
    }
  }
}

Future<ui.Image> _rasterCopy(ui.Image source) async {
  final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('Could not read original image pixels.');
  final result = Completer<ui.Image>();
  var expired = false;
  ui.decodeImageFromPixels(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    source.width,
    source.height,
    ui.PixelFormat.rgba8888,
    (image) {
      if (expired) {
        image.dispose();
      } else {
        result.complete(image);
      }
    },
  );
  return result.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      expired = true;
      throw StateError(
        'Original image pixel conversion timed out. Retry export.',
      );
    },
  );
}

Float64List _matrix(Transform2 t) => Float64List.fromList([
  t.a,
  t.b,
  0,
  0,
  t.c,
  t.d,
  0,
  0,
  0,
  0,
  1,
  0,
  t.tx,
  t.ty,
  0,
  1,
]);
