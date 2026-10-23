// Runs inside the target OS Flutter engine, with an isolated disposable store.
// Reopening below restarts app widgets and store handles, not the OS process.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whiteboard/main.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/png_export.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/persistence/file_board_store.dart';
import 'package:whiteboard/src/persistence/portable_project.dart';
import 'package:whiteboard/src/viewport/camera.dart';

import '../test/png_export_aspect_test.dart' show pngAspectFixture;
import '../test/png_export_test.dart' show at, pixels;
import '../test/support/image_test_bytes.dart';

EditorCanvasController _canvas(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).controller;

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final timeout = DateTime.now().add(const Duration(seconds: 30));
  do {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  } while (DateTime.now().isBefore(timeout));
  fail('Timed out waiting for $description.');
}

Future<void> _saved(WidgetTester tester) => _waitFor(
  tester,
  () => find.text('Saved locally').evaluate().isNotEmpty,
  'acknowledged local save',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final stores = <FileBoardStore>[];

  Future<FileBoardStore> openStore({WidgetTester? afterDisposal}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final store = FileBoardStore(directory);
      stores.add(store);
      await store.initialize();
      if (store.writable) return store;
      await store.close();
      // Workspace disposal owns an asynchronous save/close drain. Wait for its
      // actual lock release before asking a new handle to become the writer.
      if (afterDisposal == null || DateTime.now().isAfter(deadline)) {
        fail('The isolated workspace writer lock was not released.');
      }
      await afterDisposal.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('blanko-native-smoke-');
  });
  tearDown(() async {
    for (final store in stores.reversed) {
      await store.close();
    }
    stores.clear();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets(
    'real editor drawing and original assets survive store reopening',
    (tester) async {
      final store = await openStore();
      await tester.pumpWidget(WhiteboardApp(store: store));
      await _waitFor(
        tester,
        () => find.byType(EditorCanvas).evaluate().isNotEmpty,
        'normal Editor startup',
      );
      await _saved(tester);
      final controller = _canvas(tester);
      controller.setTool(EditorTool.pen);
      await tester.pump();
      final area = tester.getRect(find.byKey(const ValueKey('board-canvas')));
      final start = area.center + const Offset(-45, -30);
      final pointer = await tester.startGesture(
        start,
        kind: Platform.isAndroid || Platform.isIOS
            ? PointerDeviceKind.touch
            : PointerDeviceKind.mouse,
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
      controller.undo();
      expect(controller.elementCount, 0);
      controller.redo();
      expect(controller.elementCount, 1);

      final imageId = await controller.importImage(
        bytes: imageTestPng(),
        filename: 'native-smoke.png',
        mimeType: 'image/png',
      );
      expect(imageId, isNotNull, reason: controller.message);
      await tester.pump();
      await _saved(tester);
      final before = controller.session.document;
      final documentBytes = DocumentCodec.encode(before);
      final camera = controller.camera;
      final image = before.byId[imageId]!.content as ImageElementContent;
      expect(
        await store.readAsset(image.assetId),
        orderedEquals(imageTestPng()),
      );
      expect(
        DocumentCodec.encode((await store.readBoard(before.id))!.document),
        documentBytes,
      );
      expect(await store.readLastBoard(), before.id);

      // Disposing WhiteboardApp drains its save queue; closing is idempotent.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await store.close();
      final reopened = await openStore();
      await tester.pumpWidget(WhiteboardApp(store: reopened));
      await _waitFor(
        tester,
        () => find.byType(EditorCanvas).evaluate().isNotEmpty,
        'Editor reopening from disk',
      );
      await _saved(tester);
      final restored = _canvas(tester);
      expect(DocumentCodec.encode(restored.session.document), documentBytes);
      expect(restored.camera.zoom, camera.zoom);
      expect(restored.camera.translation, camera.translation);
      expect(restored.session.canUndo, isFalse);
      expect(
        await reopened.readAsset(image.assetId),
        orderedEquals(imageTestPng()),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('portable project and PNG use real files and native rendering', (
    tester,
  ) async {
    final store = await openStore();
    final document = pngAspectFixture();
    final originalDocument = DocumentCodec.encode(document);
    await store.writeAsset('aspect-image', imageTestPng());
    final snapshot = BoardSnapshot(
      document: document,
      camera: Camera(translation: Point2(15, 25), zoom: 1.5),
      version: 1,
      savedAt: DateTime.utc(2026, 10, 23),
    );
    await store.writeBoard(snapshot, expectedVersion: null);
    final projectFile = File('${directory.path}/native-smoke.wboard');
    await projectFile.writeAsBytes(
      await exportPortableProject(snapshot, store),
      flush: true,
    );
    final project = decodePortableProject(await projectFile.readAsBytes());
    expect(project.assets['aspect-image'], orderedEquals(imageTestPng()));
    final imported = await importPortableProject(
      project,
      store,
      boardId: 'native-smoke-import',
      assetPrefix: 'native-smoke-original',
    );
    expect(imported.document.id, isNot(document.id));
    expect(
      imported.document.elements.map((e) => e.id),
      document.elements.map((e) => e.id),
    );
    expect(imported.camera.translation, snapshot.camera.translation);
    expect(imported.camera.zoom, snapshot.camera.zoom);
    final importedAsset = imported.document.assets!.single;
    expect(
      await store.readAsset(importedAsset.id),
      orderedEquals(imageTestPng()),
    );
    await store.close();
    final reopened = await openStore(afterDisposal: tester);
    final persisted = (await reopened.readBoard(imported.document.id))!;
    expect(persisted.encode(), imported.encode());

    final png = await renderBoardPng(
      document: persisted.document,
      store: reopened,
      bounds: Bounds2(0, 0, 600, 400),
      frameId: ElementId('aspect-frame'),
      width: 900,
      height: 400,
    );
    final pngFile = File('${directory.path}/native-smoke.png');
    await pngFile.writeAsBytes(png, flush: true);
    expect(await pngFile.readAsBytes(), orderedEquals(png));
    final header = ByteData.sublistView(png);
    expect((header.getUint32(16), header.getUint32(20)), (900, 400));
    final rendered = await pixels(await pngFile.readAsBytes());
    expect((rendered.width, rendered.height), (900, 400));
    expect(at(rendered.pixels, 900, 25, 200), [0, 0, 0, 0]);
    expect(at(rendered.pixels, 900, 100, 200), [0, 0, 0, 0]);
    var left = rendered.width, top = rendered.height, right = -1, bottom = -1;
    for (var y = 0; y < rendered.height; y++) {
      for (var x = 0; x < rendered.width; x++) {
        final offset = (y * rendered.width + x) * 4;
        if (rendered.pixels[offset] == 34 &&
            rendered.pixels[offset + 1] == 102 &&
            rendered.pixels[offset + 2] == 221 &&
            rendered.pixels[offset + 3] == 255) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    final circleWidth = right - left + 1;
    final circleHeight = bottom - top + 1;
    expect(circleWidth, inInclusiveRange(118, 120));
    expect(circleHeight, inInclusiveRange(118, 120));
    expect((circleWidth - circleHeight).abs(), lessThanOrEqualTo(1));
    expect(left, inInclusiveRange(190, 191));
    expect(top, inInclusiveRange(80, 81));
    expect(DocumentCodec.encode(document), originalDocument);
    expect((await reopened.listBoards()).length, 2);
  });

  testWidgets('native file bridge rejects unsafe output without a picker', (
    tester,
  ) async {
    // A deliberately invalid supported call proves native handler registration.
    // Unknown calls cannot: registered and missing handlers both return notImplemented.
    // This does not verify the actual system chooser or document providers.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    await expectLater(
      const MethodChannel('blanko/project_files')
          .invokeMethod<bool>('saveFile', {
            'bytes': Uint8List(0),
            'suggestedName': 'native-smoke.invalid',
            'extension': 'invalid',
          })
          .timeout(const Duration(seconds: 10)),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'invalid_file',
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
