import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'support/image_test_bytes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/viewport/camera.dart';
import 'support/test_board_store.dart';
import 'workspace_widget_test.dart' as workspace;

Future<Uint8List> png() async => imageTestPng();

class DelayedAssets extends TestBoardStore {
  final gate = Completer<void>();
  @override
  Future<void> writeAsset(String id, Uint8List bytes) async {
    await gate.future;
    await super.writeAsset(id, bytes);
  }
}

void main() {
  testWidgets('import decodes persisted originals at the viewport center', (
    tester,
  ) async {
    final store = TestBoardStore();
    final controller = EditorCanvasController(store: store)
      ..viewportSize = const Size(1000, 700)
      ..camera = Camera(translation: Point2(-200, 80), zoom: 2);
    addTearDown(controller.dispose);
    final bytes = await png();
    await tester.runAsync(() async {
      final id = await controller.importImage(
        bytes: bytes,
        filename: 'sample.png',
      );
      expect(id, isNotNull, reason: controller.message);
      final asset = controller.session.document.assets!.single;
      expect(store.assets[asset.id], orderedEquals(bytes));
      final image = controller.imageCache.get(asset.id);
      expect(image, isNotNull, reason: controller.imageCache.errors.toString());
      final content =
          controller.session.document.byId[id]!.content as ImageElementContent;
      expect(
        content.bounds.center,
        controller.camera.viewportToWorld(Point2(500, 350)),
      );
      expect(content.bounds.width / content.bounds.height, 2);
      controller.undo();
      expect(controller.elementCount, 0);
      controller.redo();
      expect(controller.elementCount, 1);
      controller.selectedId = id;
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.rotateSelection();
      expect(notifications, 1);
      controller.duplicateSelection();
      expect(notifications, 2);
      expect(controller.elementCount, 2);
      expect(controller.session.document.assets, hasLength(1));
    });
  });

  testWidgets('storage failure or missing storage commits no image', (
    tester,
  ) async {
    final bytes = await png();
    for (final store in [null, TestBoardStore()..readOnly = true]) {
      final controller = EditorCanvasController(store: store);
      await tester.runAsync(() async {
        expect(
          await controller.importImage(bytes: bytes, filename: 'sample.png'),
          isNull,
        );
      });
      expect(controller.elementCount, 0);
      expect(controller.message, isNotNull);
      controller.dispose();
    }
  });

  testWidgets('disposed import cannot commit after delayed asset write', (
    tester,
  ) async {
    final bytes = await png();
    await tester.runAsync(() async {
      final store = DelayedAssets();
      final controller = EditorCanvasController(store: store);
      final pending = controller.importImage(
        bytes: bytes,
        filename: 'sample.png',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      controller.dispose();
      store.gate.complete();
      expect(await pending, isNull);
      expect(controller.session.document.elements, isEmpty);
    });
  });

  testWidgets(
    'image autosave delete undo redo and simulated reopening preserve originals',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      final bytes = await png();
      var controller = workspace.canvas(tester);
      await tester.runAsync(() async {
        expect(
          await controller.importImage(bytes: bytes, filename: 'sample.png'),
          isNotNull,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('Saved locally'), findsOneWidget);
      final asset = controller.session.document.assets!.single.id;
      await workspace.restart(tester, store);
      controller = workspace.canvas(tester);
      expect(controller.elementCount, 1);
      controller.selectedId = controller.session.document.elements.single.id;
      controller.deleteSelection();
      await tester.pumpAndSettle();
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.elementCount, 1);
      controller.redo();
      await tester.pumpAndSettle();
      await workspace.restart(tester, store);
      expect(workspace.canvas(tester).elementCount, 0);
      expect(store.assets[asset], orderedEquals(bytes));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
