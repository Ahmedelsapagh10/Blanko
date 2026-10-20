import 'dart:io';

import 'image_picker_stub.dart';

bool get supportsImagePicking => Platform.isMacOS;

Future<PickedImage?> pickImageFile() async {
  if (Platform.isMacOS) {
    try {
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose file of type {"public.image"})',
      ]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final name = file.uri.pathSegments.last;
            final ext = name.split('.').last.toLowerCase();
            final mime = switch (ext) {
              'png' => 'image/png',
              'jpg' || 'jpeg' => 'image/jpeg',
              'webp' => 'image/webp',
              'gif' => 'image/gif',
              'bmp' => 'image/bmp',
              _ => 'image/png',
            };
            return PickedImage(bytes: bytes, filename: name, mimeType: mime);
          }
        }
      }
    } catch (_) {}
  }
  return null;
}
