import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../persistence/portable_project.dart';

/// Verifies original dimensions and first-frame decoding without store writes.
/// Web's framework helper temporarily decodes the original before its thumbnail.
Future<void> validatePortableImages(PortableProject project) async {
  const maximumOriginalPixels = 64 * 1000 * 1000;
  final references = project.snapshot.document.assets!;
  // Reject unsafe declarations before allocating any decoder resources.
  for (final reference in references) {
    if (reference.pixelWidth! * reference.pixelHeight! >
        maximumOriginalPixels) {
      throw const FormatException(
        'Project images above 64 million original pixels are not supported.',
      );
    }
  }
  for (final reference in references) {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    ui.TargetImageSize targetSize(int width, int height) {
      if (width != reference.pixelWidth || height != reference.pixelHeight) {
        throw FormatException(
          'Original image ${reference.id} dimensions do not match its declaration.',
        );
      }
      if (width * height > maximumOriginalPixels) {
        throw const FormatException(
          'Project images above 64 million original pixels are not supported.',
        );
      }
      final scale = math.min(1.0, 64 / math.max(width, height));
      return ui.TargetImageSize(
        width: math.max(1, (width * scale).floor()),
        height: math.max(1, (height * scale).floor()),
      );
    }

    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(
        // Web engine requires a native typed list, not an unmodifiable view.
        Uint8List.fromList(project.assets[reference.id]!),
      );
      if (kIsWeb) {
        final source = buffer;
        buffer = null;
        // The Web helper owns the source buffer even when decoding throws.
        codec = await ui.instantiateImageCodecWithSize(
          source,
          getTargetSize: targetSize,
        );
      } else {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final target = targetSize(descriptor.width, descriptor.height);
        codec = await descriptor.instantiateCodec(
          targetWidth: target.width,
          targetHeight: target.height,
        );
      }
      image = (await codec.getNextFrame()).image;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException(
        'Original image ${reference.id} is damaged or unsupported ($error). The current board has not changed.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
