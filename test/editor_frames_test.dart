import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document_geometry.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/editor/editor_page.dart';
import 'package:whiteboard/src/editor/frame_properties_dialog.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/theme/blanko_brand.dart';

import 'editor_widget_test.dart' as editor;
import 'support/test_board_store.dart';
import 'workspace_widget_test.dart' as workspace;

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Future<void> _frame(WidgetTester tester, {bool export = false}) async {
  await tester.tap(find.byTooltip('More tools'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(export ? 'Export frame' : 'Frame (F)'));
  await tester.pumpAndSettle();
  await editor.drag(tester, const Offset(100, 100), const Offset(400, 350));
  await tester.tap(find.byTooltip('Select (V)'));
  await tester.pump();
}

Future<void> _rectangle(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Shapes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rectangle (R)'));
  await tester.pumpAndSettle();
  await editor.drag(tester, const Offset(160, 160), const Offset(250, 230));
  await tester.tap(find.byTooltip('Select (V)'));
  await tester.pump();
}

Future<void> _place(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Place in frame'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'rotated container corner resize preserves child world transform and Undo',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final frameId = ElementId('rotated-frame');
      final childId = ElementId('frame-child');
      final transform =
          Transform2.translation(250, 200) * Transform2.rotation(math.pi / 4);
      final originalBounds = Bounds2(0, 0, 200, 100);
      final session = BoardSession(
        document: BoardDocument(
          id: 'rotated-frame-board',
          revision: 0,
          assets: const [],
          fontReferences: const [],
          elements: [
            DocumentElement(
              id: frameId,
              transform: transform,
              content: ContainerFrameElementContent(
                bounds: originalBounds,
                label: 'Rotated',
              ),
            ),
            DocumentElement(
              id: childId,
              parentId: frameId,
              transform: Transform2.translation(30, 25),
              content: ShapeElementContent(
                kind: ShapeKind.rectangle,
                bounds: Bounds2(0, 0, 40, 30),
                fillColor: 0xff15191f,
              ),
            ),
          ],
        ),
      );
      final c = EditorCanvasController(session: session)
        ..setTool(EditorTool.select)
        ..selectedId = frameId;
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(home: EditorPage(controller: c)));
      await tester.pump();
      final childWorld = c.scene.worldTransformOf(childId);
      final original = c.session.document;
      final origin = editor.canvasOrigin(tester);
      final corner = c.camera.worldToViewport(
        transform.apply(Point2(200, 100)),
      );
      final expandedCorner = c.camera.worldToViewport(
        transform.apply(Point2(250, 150)),
      );
      final gesture = await tester.startGesture(
        origin + Offset(corner.x, corner.y),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(origin + Offset(expandedCorner.x, expandedCorner.y));
      await tester.pump();
      expect(c.session.document, same(original));
      expect(c.scene.worldTransformOf(childId), childWorld);
      await gesture.up();
      await tester.pump();
      final resized =
          c.session.document.byId[frameId]!.content
              as ContainerFrameElementContent;
      expect(resized.bounds.left, closeTo(0, 1e-8));
      expect(resized.bounds.top, closeTo(0, 1e-8));
      expect(resized.bounds.width, closeTo(250, 1e-8));
      expect(resized.bounds.height, closeTo(150, 1e-8));
      expect(c.session.document.byId[frameId]!.transform, transform);
      expect(c.scene.worldTransformOf(childId), childWorld);
      expect(c.session.document.revision, original.revision + 1);
      c.undo();
      await tester.pump();
      expect(
        (c.session.document.byId[frameId]!.content
                as ContainerFrameElementContent)
            .bounds,
        originalBounds,
      );
      expect(c.scene.worldTransformOf(childId), childWorld);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'real export-frame tool, border selection and atomic properties Undo',
    (tester) async {
      await editor.open(tester);
      await _frame(tester, export: true);
      final c = editor.controller(tester);
      final id = c.session.document.elements.single.id;
      // Interior stays available for artwork; border selects the export region.
      await tester.tapAt(editor.canvasOrigin(tester) + const Offset(200, 200));
      await tester.pump();
      expect(c.selectedId, isNull);
      await tester.tapAt(editor.canvasOrigin(tester) + const Offset(100, 220));
      await tester.pump();
      expect(c.selectedId, id);
      final revision = c.session.document.revision;
      await tester.tap(find.byTooltip('Frame properties'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Frame name'), 'Presentation لوحة');
      await tester.enterText(_field('Canvas width'), '640');
      await tester.enterText(_field('Canvas height'), '360');
      await tester.enterText(_field('Output width (px)'), '3840');
      await tester.enterText(_field('Output height (px)'), '2160');
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      var content =
          c.session.document.byId[id]!.content as ExportFrameElementContent;
      expect(content.label, 'Presentation لوحة');
      expect(content.bounds.width, 640);
      expect(content.bounds.height, 360);
      expect(content.outputWidth, 3840);
      expect(content.outputHeight, 2160);
      expect(c.session.document.revision, revision + 1);
      await tester.tap(find.byTooltip('Undo (⌘/Ctrl Z)'));
      await tester.pump();
      content =
          c.session.document.byId[id]!.content as ExportFrameElementContent;
      expect(content.label, 'Export');
      expect(content.bounds.width, 300);
      expect(content.outputWidth, isNull);
      await tester.tap(find.byTooltip('Redo (⌘/Ctrl Shift Z)'));
      await tester.pump();
      expect(
        (c.session.document.byId[id]!.content as ExportFrameElementContent)
            .label,
        'Presentation لوحة',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'place/detach popup preserves world position; frame drag previews descendants',
    (tester) async {
      await editor.open(tester);
      await _frame(tester);
      final c = editor.controller(tester);
      final frameId = c.session.document.elements.single.id;
      await _rectangle(tester);
      final shape = c.session.document.elements.last;
      final original = c.scene.worldTransformOf(shape.id);
      await _place(tester, 'Frame');
      expect(c.session.document.byId[shape.id]!.parentId, frameId);
      expect(c.scene.worldTransformOf(shape.id), original);
      await _place(tester, 'Move to canvas (detach)');
      expect(c.session.document.byId[shape.id]!.parentId, isNull);
      expect(c.scene.worldTransformOf(shape.id), original);
      await _place(tester, 'Frame');
      final origin = editor.canvasOrigin(tester);
      await tester.tapAt(origin + const Offset(100, 250));
      await tester.pump();
      expect(c.selectedId, frameId);
      final committed = c.session.document;
      final gesture = await tester.startGesture(
        origin + const Offset(100, 250),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(origin + const Offset(150, 280));
      await tester.pump();
      expect(c.session.document, same(committed));
      expect(c.moveDelta, Point2(50, 30));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('board-canvas')),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          // The rectangle top edge moved from y160 to y190 during preview.
          final pixel = (190 * image.width + 230) * 4;
          expect(bytes.getUint8(pixel), lessThan(90));
          expect(bytes.getUint8(pixel + 1), lessThan(90));
        } finally {
          image.dispose();
        }
      });
      await gesture.up();
      await tester.pump();
      final moved = c.scene.worldTransformOf(shape.id);
      expect(moved.tx, original.tx + 50);
      expect(moved.ty, original.ty + 30);
      c.undo();
      await tester.pump();
      expect(c.scene.worldTransformOf(shape.id), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'container corner resize adjusts region without scaling children',
    (tester) async {
      await editor.open(tester);
      await _frame(tester);
      final c = editor.controller(tester);
      final frameId = c.session.document.elements.single.id;
      await _rectangle(tester);
      final shapeId = c.selectedId!;
      await _place(tester, 'Frame');
      final original = c.scene.worldTransformOf(shapeId);
      await tester.tapAt(editor.canvasOrigin(tester) + const Offset(100, 250));
      await tester.pump();
      expect(c.selectedId, frameId);
      // Selection handle is four viewport pixels beyond the actual frame corner.
      final before = c.session.document;
      await editor.drag(tester, const Offset(404, 354), const Offset(504, 414));
      final content =
          c.session.document.byId[frameId]!.content
              as ContainerFrameElementContent;
      expect(content.bounds.width, 404);
      expect(content.bounds.height, 314);
      expect(c.scene.worldTransformOf(shapeId), original);
      expect(c.session.document.revision, before.revision + 1);
      c.undo();
      await tester.pump();
      expect(
        (c.session.document.byId[frameId]!.content
                as ContainerFrameElementContent)
            .bounds
            .width,
        300,
      );
      expect(c.scene.worldTransformOf(shapeId), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'autosave and simulated reopening preserve frame metadata, ownership and moves',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      await _frame(tester);
      var c = workspace.canvas(tester);
      final frameId = c.selectedId!;
      c.updateSelectedFrame(label: 'Container لوحة');
      await tester.pumpAndSettle();
      await _rectangle(tester);
      final shapeId = c.selectedId!;
      await _place(tester, 'Container لوحة');
      await tester.tapAt(editor.canvasOrigin(tester) + const Offset(100, 250));
      await editor.drag(tester, const Offset(100, 250), const Offset(145, 280));
      final world = c.scene.worldTransformOf(shapeId);
      await _frame(tester, export: true);
      final exportId = c.selectedId!;
      c.updateSelectedFrame(
        label: 'Export saved',
        outputWidth: 3840,
        outputHeight: 2160,
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved locally'), findsOneWidget);
      final documentId = c.session.document.id;
      final revision = c.session.document.revision;
      await workspace.restart(tester, store);
      c = workspace.canvas(tester);
      expect(c.session.document.id, documentId);
      expect(c.session.document.revision, revision);
      expect(c.session.document.byId[shapeId]!.parentId, frameId);
      expect(
        DocumentGeometry(c.session.document).worldTransformOf(shapeId),
        world,
      );
      final exported =
          c.session.document.byId[exportId]!.content
              as ExportFrameElementContent;
      expect(exported.label, 'Export saved');
      expect(exported.outputWidth, 3840);
      expect(exported.outputHeight, 2160);
      expect(c.session.canUndo, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow dark frame dialog validates dimensions and cancellation stays immutable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = BoardSession();
      final id = session.insert(
        ExportFrameElementContent(
          bounds: Bounds2(0, 0, 200, 100),
          label: 'Mobile',
        ),
      );
      final c = EditorCanvasController(session: session);
      c.setTool(EditorTool.select);
      c.selectedId = id;
      await tester.pumpWidget(
        MaterialApp(
          theme: BlankoTheme.dark,
          home: EditorPage(controller: c),
        ),
      );
      await tester.pump();
      final document = c.session.document;
      final context = tester.element(find.byType(EditorPage));
      final dialog = showFrameProperties(context, c);
      await tester.pumpAndSettle();
      await tester.enterText(_field('Output width (px)'), '99999');
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter positive frame sizes'), findsOneWidget);
      expect(c.session.document, same(document));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await dialog;
      expect(c.session.document, same(document));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
