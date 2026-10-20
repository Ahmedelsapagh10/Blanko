import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'image_picker_stub.dart';

const supportsImagePicking = true;

Future<PickedImage?> pickImageFile() async {
  final completer = Completer<PickedImage?>();
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = 'image/*';
  input.style.display = 'none';

  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      try {
        final arrayBuffer = reader.result as JSArrayBuffer;
        final bytes = arrayBuffer.toDart.asUint8List();
        final name = file.name;
        var mime = file.type;
        if (mime.isEmpty || !mime.startsWith('image/')) {
          mime = 'image/png';
        }
        if (!completer.isCompleted) {
          completer.complete(
            PickedImage(bytes: bytes, filename: name, mimeType: mime),
          );
        }
      } catch (_) {
        if (!completer.isCompleted) completer.complete(null);
      }
    }).toJS;
    reader.onerror = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS;
    reader.readAsArrayBuffer(file);
  }).toJS;

  input.oncancel = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }).toJS;

  web.document.body?.appendChild(input);
  input.click();
  input.remove();

  return completer.future;
}
