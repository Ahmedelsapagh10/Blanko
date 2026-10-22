@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/image_picker_io.dart' as images;
import 'package:whiteboard/src/editor/project_file_gateway_io.dart' as projects;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const imageChannel = MethodChannel('blanko/image_picker');
  const projectChannel = MethodChannel('blanko/project_files');

  tearDown(() {
    messenger.setMockMethodCallHandler(imageChannel, null);
    messenger.setMockMethodCallHandler(projectChannel, null);
  });

  test('native file capabilities include mobile and macOS hosts', () {
    final supported = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    expect(images.supportsImagePicking, supported);
    expect(projects.supportsProductFiles, supported);
  });

  test(
    'image channel preserves selected bytes and distinguishes cancellation and errors',
    () async {
      final bytes = Uint8List.fromList([137, 80, 78, 71]);
      messenger.setMockMethodCallHandler(imageChannel, (call) async {
        expect(call.method, 'pickImage');
        return {
          'bytes': bytes,
          'filename': 'Mobile.png',
          'mimeType': 'image/png',
        };
      });
      final picked = await images.pickImageFile();
      expect(picked!.bytes, bytes);
      expect(picked.filename, 'Mobile.png');
      expect(picked.mimeType, 'image/png');
      messenger.setMockMethodCallHandler(imageChannel, (_) async => null);
      expect(await images.pickImageFile(), isNull);
      messenger.setMockMethodCallHandler(
        imageChannel,
        (_) async => throw PlatformException(code: 'busy'),
      );
      await expectLater(
        images.pickImageFile(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'busy',
          ),
        ),
      );
    },
    skip: !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS),
  );

  test(
    'project and PNG exports use the existing mobile channel contract',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      messenger.setMockMethodCallHandler(projectChannel, (call) async {
        if (call.method == 'pickProject') return bytes;
        expect(call.method, 'saveFile');
        expect(call.arguments['bytes'], bytes);
        expect(
          call.arguments['suggestedName'],
          'Mobile.${call.arguments['extension']}',
        );
        return true;
      });
      expect(await projects.pickProjectFile(), bytes);
      for (final extension in ['wboard', 'png']) {
        expect(
          await projects.saveProductFile(
            bytes: bytes,
            suggestedName: 'Mobile.$extension',
            extension: extension,
          ),
          isTrue,
        );
      }
      messenger.setMockMethodCallHandler(projectChannel, (_) async => false);
      expect(
        await projects.saveProductFile(
          bytes: bytes,
          suggestedName: 'Mobile.png',
          extension: 'png',
        ),
        isFalse,
      );
      messenger.setMockMethodCallHandler(
        projectChannel,
        (_) async => throw PlatformException(code: 'write_failed'),
      );
      await expectLater(
        projects.saveProductFile(
          bytes: bytes,
          suggestedName: 'Mobile.png',
          extension: 'png',
        ),
        throwsA(isA<PlatformException>()),
      );
    },
    skip: !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS),
  );
}
