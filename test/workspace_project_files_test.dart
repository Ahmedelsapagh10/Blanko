@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/project_file_gateway.dart'
    show supportsProductFiles;
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/persistence/portable_project.dart';
import 'package:whiteboard/src/viewport/camera.dart';

import 'support/image_test_bytes.dart';
import 'support/test_board_store.dart';
import 'workspace_widget_test.dart' as workspace;

const _channel = MethodChannel('blanko/project_files');

Future<void> _choose(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('Files & export'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pump();
}

Future<void> _finish(WidgetTester tester) async {
  // Engine decoding completes outside the widget fake clock. Alternate real
  // engine turns and UI frames, rather than timing out on a busy spinner.
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (workspace.canvas(tester).inputEnabled) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Project operation did not finish.');
}

Future<Uint8List> _projectFixture() async {
  final original = imageTestPng();
  final source = TestBoardStore()..assets['original'] = original;
  return exportPortableProject(
    BoardSnapshot(
      document: BoardDocument(
        id: 'external-source',
        revision: 0,
        title: 'Imported artwork',
        assets: [
          DocumentAssetReference(
            id: 'original',
            mimeType: 'image/png',
            pixelWidth: 64,
            pixelHeight: 32,
            byteLength: original.length,
          ),
        ],
        fontReferences: [],
        elements: [
          DocumentElement(
            id: ElementId('image'),
            content: ImageElementContent(
              assetId: 'original',
              bounds: Bounds2(0, 0, 64, 32),
            ),
          ),
          DocumentElement(
            id: ElementId('export-frame'),
            content: ExportFrameElementContent(
              bounds: Bounds2(0, 0, 100, 100),
              label: 'Print',
              outputWidth: 1024,
              outputHeight: 768,
            ),
          ),
        ],
      ),
      camera: Camera(translation: Point2(15, 25), zoom: 1.5),
      version: 1,
      savedAt: DateTime.utc(2026, 10, 20),
    ),
    source,
  );
}

void main() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  testWidgets(
    'Save As exports committed artwork and original image bytes without changing the board',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      final controller = workspace.canvas(tester);
      final original = imageTestPng();
      await tester.runAsync(
        () => controller.importImage(bytes: original, filename: 'original.png'),
      );
      await tester.pumpAndSettle();
      final before = store.records[controller.session.document.id];
      MethodCall? saved;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        saved = call;
        return true;
      });

      await _choose(tester, 'Save As .wboard');
      await _finish(tester);
      expect(saved!.method, 'saveFile');
      expect(saved!.arguments['extension'], 'wboard');
      final project = decodePortableProject(
        saved!.arguments['bytes'] as Uint8List,
      );
      expect(project.assets.values.single, orderedEquals(original));
      expect(project.snapshot.document.id, controller.session.document.id);
      expect(project.snapshot.document.elements, hasLength(1));
      expect(store.records, hasLength(1));
      expect(store.records[controller.session.document.id], before);
      expect(find.text('Project file saved.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !supportsProductFiles,
  );

  testWidgets(
    'Import creates an independent durable board and restores it on simulated reopening',
    (tester) async {
      final projectBytes = await _projectFixture();
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await workspace.pen(tester);
      await tester.pumpAndSettle();
      final previousId = store.last!;
      final previousBytes = store.records[previousId];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        expect(call.method, 'pickProject');
        return projectBytes;
      });

      await _choose(tester, 'Import .wboard');
      await _finish(tester);
      final controller = workspace.canvas(tester);
      final imported = controller.session.document;
      expect(imported.id, isNot(previousId));
      expect(imported.id, isNot('external-source'));
      expect(imported.title, 'Imported artwork');
      expect(controller.camera.zoom, 1.5);
      expect(controller.camera.translation, Point2(15, 25));
      expect(imported.elements.map((e) => e.id.value), [
        'image',
        'export-frame',
      ]);
      final frame = imported.elements.last.content as ExportFrameElementContent;
      expect(
        (frame.label, frame.outputWidth, frame.outputHeight),
        ('Print', 1024, 768),
      );
      final assetId =
          (imported.elements.first.content as ImageElementContent).assetId;
      expect(assetId, isNot('original'));
      expect(store.assets[assetId], orderedEquals(imageTestPng()));
      expect(store.last, imported.id);
      expect(store.records[previousId], previousBytes);
      expect(store.records, hasLength(2));
      expect(controller.session.canUndo, isFalse);
      await workspace.restart(tester, store);
      expect(workspace.canvas(tester).session.document.id, imported.id);
      expect(workspace.canvas(tester).elementCount, 2);
      expect(workspace.canvas(tester).camera.zoom, 1.5);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !supportsProductFiles,
  );

  testWidgets(
    'corrupt import and native picker failure retain current artwork and storage',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await workspace.pen(tester);
      await tester.pumpAndSettle();
      final controller = workspace.canvas(tester);
      final records = Map<String, String>.of(store.records);
      final last = store.last;
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => Uint8List.fromList([1, 2, 3]),
      );
      await _choose(tester, 'Import .wboard');
      await _finish(tester);
      expect(workspace.canvas(tester), same(controller));
      expect(controller.elementCount, 1);
      expect(store.records, records);
      expect(store.last, last);
      expect(store.assets, isEmpty);
      expect(find.textContaining('Could not import project:'), findsOneWidget);
      // Let the earlier feedback expire before testing another recoverable error.
      await tester.pump(const Duration(seconds: 9));
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(code: 'read_failed'),
      );
      await _choose(tester, 'Import .wboard');
      await _finish(tester);
      expect(workspace.canvas(tester), same(controller));
      expect(store.records, records);
      expect(store.last, last);
      expect(find.textContaining('Could not import project:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !supportsProductFiles,
  );

  testWidgets(
    'pending Save As disables edits and switching until native acknowledgement',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await workspace.pen(tester);
      await tester.pumpAndSettle();
      final controller = workspace.canvas(tester);
      final revision = controller.session.document.revision;
      late Completer<bool> gate;
      await tester.runAsync(() async {
        gate = Completer<bool>();
      });
      var requests = 0;
      messenger.setMockMethodCallHandler(_channel, (_) async {
        requests++;
        return gate.future;
      });
      await _choose(tester, 'Save As .wboard');
      expect(controller.inputEnabled, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.folder_open_outlined),
            )
            .onPressed,
        isNull,
      );
      controller.undo();
      controller.duplicateSelection();
      expect(controller.session.document.revision, revision);
      expect(requests, 1);
      await tester.runAsync(() async {
        gate.complete(true);
      });
      await _finish(tester);
      expect(controller.inputEnabled, isTrue);
      expect(controller.session.document.revision, revision);
      expect(requests, 1);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !supportsProductFiles,
  );
}
