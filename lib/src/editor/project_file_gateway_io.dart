import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('blanko/project_files');
const _maximumBytes = 128 * 1024 * 1024;

bool get supportsProductFiles => Platform.isMacOS;

Future<Uint8List?> pickProjectFile() async {
  if (!supportsProductFiles) {
    throw UnsupportedError(
      'Project import is currently available on macOS and Web.',
    );
  }
  final bytes = await _channel.invokeMethod<Uint8List>('pickProject');
  if (bytes != null && bytes.length > _maximumBytes) {
    throw StateError('Project file exceeds the 128 MiB limit.');
  }
  return bytes;
}

Future<bool> saveProductFile({
  required Uint8List bytes,
  required String suggestedName,
  required String extension,
}) async {
  if (!supportsProductFiles) {
    throw UnsupportedError(
      'File saving is currently available on macOS and Web.',
    );
  }
  if (bytes.isEmpty || bytes.length > _maximumBytes) {
    throw ArgumentError('File must contain between 1 byte and 128 MiB.');
  }
  if (extension != 'png' && extension != 'wboard') {
    throw ArgumentError.value(extension, 'extension', 'Unsupported file type.');
  }
  return await _channel.invokeMethod<bool>('saveFile', {
        'bytes': bytes,
        'suggestedName': suggestedName,
        'extension': extension,
      }) ??
      false;
}
