import 'dart:typed_data';

final class PickedImage {
  PickedImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

Future<PickedImage?> pickImageFile() async => null;
