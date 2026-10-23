// Dedicated CI entrypoint. Run the same Release executable with "write", then
// "read" and a report path in separate processes. Never use an owner's profile.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whiteboard/main.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/persistence/file_board_store.dart';

import '../test/support/image_test_bytes.dart';

const _enabled = bool.fromEnvironment('WB_WINDOWS_RELEASE_SMOKE');
late final File _resultFile;

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  do {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  } while (DateTime.now().isBefore(deadline));
  fail('Timed out waiting for $description.');
}

EditorCanvasController _canvas(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).controller;

Future<void> _openEditor(WidgetTester tester) async {
  // This is the real application composition, including the default directory
  // provider, workspace lock and autosave. No store or native channel is mocked.
  await tester.pumpWidget(const WhiteboardApp());
  await _waitFor(
    tester,
    () => find.byType(EditorCanvas).evaluate().isNotEmpty,
    'normal Release Editor',
  );
  expect(_canvas(tester).readOnly, isFalse);
  await _waitFor(
    tester,
    () => find
        .byTooltip('Saved locally\nChanges are saved on this device.')
        .evaluate()
        .isNotEmpty,
    'acknowledged local save',
  );
}

Future<void> _filesMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Files & export'));
  await _waitFor(
    tester,
    () => find.text('Save As .wboard').evaluate().isNotEmpty,
    'enabled Windows file menu',
  );
  expect(find.text('Export PNG'), findsOneWidget);
  expect(find.text('Import .wboard'), findsOneWidget);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 250));

  // Exercise the real Release runner's channel registration without opening a
  // chooser. Missing native registration and unsupported methods fail this test.
  await expectLater(
    const MethodChannel('blanko/project_files').invokeMethod<bool>('saveFile', {
      'bytes': Uint8List(0),
      'suggestedName': 'invalid',
      'extension': 'wboard',
    }),
    throwsA(
      isA<PlatformException>().having(
        (error) => error.code,
        'native validation',
        'invalid_file',
      ),
    ),
  );
}

Future<void> _report(
  IntegrationTestWidgetsFlutterBinding binding,
  String phase,
) async {
  var success = false;
  String? error;
  try {
    success = await binding.allTestsPassed.future.timeout(
      const Duration(seconds: 75),
    );
    // A skipped or unregistered test must not turn this into a green CI job.
    success = success && binding.results.length == 1;
  } catch (failure) {
    error = '$failure';
  }
  try {
    await _resultFile.parent.create(recursive: true);
    await _resultFile.writeAsString(
      jsonEncode({
        'passed': success,
        'phase': phase,
        'release': kReleaseMode,
        'platform': Platform.operatingSystem,
        'tests': binding.results.map(
          (name, value) => MapEntry(name, value.toString()),
        ),
        'error': ?error,
      }),
      flush: true,
    );
  } catch (failure) {
    stderr.writeln('Could not write Release test verdict: $failure');
    exit(2);
  }
  exit(success ? 0 : 1);
}

void main(List<String> arguments) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final phase = arguments.length == 2 ? arguments.first : 'invalid';
  _resultFile = File(
    arguments.length == 2
        ? arguments.last
        : 'build/windows-release-smoke.invalid.json',
  );
  unawaited(_report(binding, phase));

  testWidgets('Windows Release $phase uses real local storage and file menu', (
    tester,
  ) async {
    expect(Platform.isWindows, isTrue);
    expect(kReleaseMode, isTrue);
    expect(
      _enabled,
      isTrue,
      reason: 'Explicit dedicated CI opt-in is required.',
    );
    expect(Platform.environment['GITHUB_ACTIONS'], 'true');
    expect(const String.fromEnvironment('WB_LOCAL_WORKSPACE'), isEmpty);
    expect(phase, isIn(['write', 'read']));
    expect(_resultFile.isAbsolute, isTrue);

    final fixtureFile = File(
      '${_resultFile.parent.path}/blanko-windows-release.fixture.json',
    );
    final store = await createBoardStore();
    await store.initialize();
    try {
      expect(store.writable, isTrue);
      if (phase == 'write') {
        // Refuse before opening the app or touching existing Board contents.
        expect(
          await store.listBoards(),
          isEmpty,
          reason: 'This test requires a clean disposable Windows CI profile.',
        );
        expect(await store.readLastBoard(), isNull);
        expect(await fixtureFile.exists(), isFalse);
      } else {
        final expected = BoardSnapshot.decode(await fixtureFile.readAsString());
        expect(await store.readLastBoard(), expected.document.id);
        final persisted = (await store.listBoards()).single;
        expect(
          DocumentCodec.encode(persisted.document),
          DocumentCodec.encode(expected.document),
        );
        expect(persisted.camera.zoom, expected.camera.zoom);
        expect(persisted.camera.translation, expected.camera.translation);
        final image = persisted.document.elements
            .map((element) => element.content)
            .whereType<ImageElementContent>()
            .single;
        expect(
          await store.readAsset(image.assetId),
          orderedEquals(imageTestPng()),
        );
      }
    } finally {
      await store.close();
    }

    await _openEditor(tester);
    await _filesMenu(tester);
    final controller = _canvas(tester);
    if (phase == 'write') {
      controller.setTool(EditorTool.pen);
      await tester.pump();
      final area = tester.getRect(find.byKey(const ValueKey('board-canvas')));
      final start = area.center + const Offset(-80, -40);
      final pointer = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await pointer.moveTo(start + const Offset(35, 20));
      await pointer.moveTo(start + const Offset(90, 45));
      await pointer.up();
      await tester.pump();
      expect(controller.elementCount, 1);
      expect(
        controller.session.document.elements.single.content,
        isA<StrokeElementContent>(),
      );
      final image = await controller.importImage(
        bytes: imageTestPng(),
        filename: 'windows-release-original.png',
        mimeType: 'image/png',
      );
      expect(image, isNotNull, reason: controller.message);
      expect(controller.elementCount, 2);
      await _waitFor(
        tester,
        () => find
            .byTooltip('Saved locally\nChanges are saved on this device.')
            .evaluate()
            .isNotEmpty,
        'drawing and original image acknowledged on disk',
      );
      await fixtureFile.parent.create(recursive: true);
      await fixtureFile.writeAsString(
        BoardSnapshot(
          document: controller.session.document,
          camera: controller.camera,
          version: 1,
          savedAt: DateTime.now().toUtc(),
        ).encode(),
        flush: true,
      );
    } else {
      final expected = BoardSnapshot.decode(await fixtureFile.readAsString());
      expect(
        DocumentCodec.encode(controller.session.document),
        DocumentCodec.encode(expected.document),
      );
      expect(controller.elementCount, 2);
      expect(controller.camera.zoom, expected.camera.zoom);
      expect(controller.camera.translation, expected.camera.translation);
      expect(controller.session.canUndo, isFalse);
    }
    expect(tester.takeException(), isNull);
    // The first process exits after acknowledged autosave. The second process
    // must acquire a fresh native writer lock and reopen the same actual Board.
  });
}
