@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/project_file_gateway_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('blanko/project_files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'project picker returns bytes, distinguishes cancel and read errors',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => Uint8List.fromList([1, 2, 3]),
      );
      expect(await pickProjectFile(), [1, 2, 3]);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await pickProjectFile(), isNull);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'read_failed'),
      );
      await expectLater(pickProjectFile(), throwsA(isA<PlatformException>()));
    },
    skip: !Platform.isMacOS,
  );

  test(
    'save sends original bytes and propagates acknowledged save or cancel',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });
      final bytes = Uint8List.fromList([10, 20, 30]);
      expect(
        await saveProductFile(
          bytes: bytes,
          suggestedName: 'Board.png',
          extension: 'png',
        ),
        isTrue,
      );
      expect(received!.method, 'saveFile');
      expect(received!.arguments['bytes'], bytes);
      expect(received!.arguments['extension'], 'png');
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(
        await saveProductFile(
          bytes: bytes,
          suggestedName: 'Board.wboard',
          extension: 'wboard',
        ),
        isFalse,
      );
    },
    skip: !Platform.isMacOS,
  );

  test(
    'save validates types and data before opening a native panel',
    () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (_) async {
        called = true;
        return true;
      });
      await expectLater(
        saveProductFile(
          bytes: Uint8List(0),
          suggestedName: 'Blank',
          extension: 'png',
        ),
        throwsArgumentError,
      );
      await expectLater(
        saveProductFile(
          bytes: Uint8List(1),
          suggestedName: 'Blank',
          extension: 'exe',
        ),
        throwsArgumentError,
      );
      expect(called, isFalse);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'save failure remains actionable rather than reporting success',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'write_failed'),
      );
      await expectLater(
        saveProductFile(
          bytes: Uint8List(1),
          suggestedName: 'Blank.png',
          extension: 'png',
        ),
        throwsA(isA<PlatformException>()),
      );
    },
    skip: !Platform.isMacOS,
  );
}
