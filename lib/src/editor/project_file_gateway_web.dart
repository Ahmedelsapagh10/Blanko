import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const supportsProductFiles = true;
const _maximumBytes = 128 * 1024 * 1024;

Future<Uint8List?> pickProjectFile() async {
  final completer = Completer<Uint8List?>();
  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = '.wboard';
  input.style.display = 'none';
  web.FileReader? activeReader;

  input.onchange = ((web.Event _) {
    if (completer.isCompleted || activeReader != null) return;
    final file = input.files?.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    if (file.size == 0 || file.size > _maximumBytes) {
      completer.completeError(
        StateError('Project file must contain between 1 byte and 128 MiB.'),
      );
      return;
    }
    final reader = web.FileReader();
    activeReader = reader;
    reader.onload = ((web.Event _) {
      if (completer.isCompleted) return;
      try {
        completer.complete(
          (reader.result as JSArrayBuffer).toDart.asUint8List(),
        );
      } catch (_) {
        completer.completeError(
          StateError('Could not read the selected project.'),
        );
      }
    }).toJS;
    reader.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Could not read the selected project.'),
        );
      }
    }).toJS;
    reader.onabort = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS;
    reader.readAsArrayBuffer(file);
  }).toJS;
  input.oncancel = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }).toJS;
  web.document.body?.appendChild(input);
  try {
    input.click();
    return await completer.future;
  } finally {
    input.onchange = null;
    input.oncancel = null;
    final reader = activeReader;
    if (reader != null) {
      reader.onload = null;
      reader.onerror = null;
      reader.onabort = null;
    }
    input.remove();
  }
}

/// True means that the browser accepted a download request. Browser settings
/// decide its destination; the page cannot certify a completed disk write.
Future<bool> saveProductFile({
  required Uint8List bytes,
  required String suggestedName,
  required String extension,
}) async {
  if (bytes.isEmpty || bytes.length > _maximumBytes) {
    throw ArgumentError('File must contain between 1 byte and 128 MiB.');
  }
  if (extension != 'png' && extension != 'wboard') {
    throw ArgumentError.value(extension, 'extension', 'Unsupported file type.');
  }
  final mime = extension == 'png' ? 'image/png' : 'application/octet-stream';
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  final name = suggestedName.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_').trim();
  anchor.href = url;
  anchor.download = name.toLowerCase().endsWith('.$extension')
      ? name
      : '${name.isEmpty ? 'Blanko' : name}.$extension';
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
    // Revoking immediately can race the browser's asynchronous download read.
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  }
  return true;
}
