import 'dart:typed_data';

const supportsProductFiles = false;

Future<Uint8List?> pickProjectFile() async =>
    throw UnsupportedError('Project files are unavailable on this platform.');

Future<bool> saveProductFile({
  required Uint8List bytes,
  required String suggestedName,
  required String extension,
}) async =>
    throw UnsupportedError('File saving is unavailable on this platform.');
