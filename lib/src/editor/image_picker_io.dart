import 'dart:io';

import 'package:flutter/services.dart';

import 'image_picker_stub.dart';

bool get supportsImagePicking => Platform.isMacOS;

Future<PickedImage?> pickImageFile() async {
  if (!supportsImagePicking) return null;
  final result = await const MethodChannel(
    'blanko/image_picker',
  ).invokeMapMethod<String, dynamic>('pickImage');
  if (result == null) return null;
  return PickedImage(
    bytes: result['bytes'] as Uint8List,
    filename: result['filename'] as String,
    mimeType: result['mimeType'] as String,
  );
}
