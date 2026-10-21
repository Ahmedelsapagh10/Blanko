import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/png_export.dart';
import 'package:whiteboard/src/persistence/portable_project.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'editor_widget_test.dart' as editor;
import 'workspace_widget_test.dart' as workspace;
import 'support/test_board_store.dart';
import 'support/drawing_tools_fixture.dart';
import 'support/image_test_bytes.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/viewport/camera.dart';

void main() {
  testWidgets(
    'smoothed pen preserves endpoints, previews tail and cancels safely',
    (tester) async {
      await editor.open(tester);
      final c = editor.controller(tester);
      final origin = editor.canvasOrigin(tester);
      final g = await tester.startGesture(
        origin + const Offset(200, 200),
        kind: PointerDeviceKind.mouse,
      );
      for (final p in [
        const Offset(230, 210),
        const Offset(260, 225),
        const Offset(300, 230),
      ]) {
        await g.moveTo(origin + p);
      }
      await tester.pump();
      expect(c.elementCount, 0);
      expect(c.previewPath, isNotNull);
      await g.up();
      await tester.pump();
      final content =
          c.session.document.elements.single.content as StrokeElementContent;
      expect(content.points.first, Point2.zero);
      expect(content.points.last, Point2(100, 30));
      expect(content.points.length, greaterThan(3));
      final document = c.session.document;
      final canceled = await tester.startGesture(
        origin + const Offset(400, 200),
        kind: PointerDeviceKind.stylus,
      );
      await canceled.moveTo(origin + const Offset(450, 250));
      await canceled.cancel();
      await tester.pump();
      expect(c.session.document, same(document));
      expect(c.previewPath, isNull);
      final switched = await tester.startGesture(
        origin + const Offset(400, 200),
        kind: PointerDeviceKind.mouse,
      );
      await switched.moveTo(origin + const Offset(500, 230));
      c.setTool(EditorTool.rectangle);
      await switched.up();
      await tester.pump();
      expect(c.session.document, same(document));
    },
  );
  testWidgets(
    'real highlighter tool is atomic, editable and erase/undo durable',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      final c = workspace.canvas(tester);
      await tester.tap(find.byTooltip('Highlighter (M)'));
      await tester.pump();
      await editor.drag(tester, const Offset(200, 250), const Offset(400, 250));
      final stroke =
          c.session.document.elements.single.content as StrokeElementContent;
      expect(stroke.kind, StrokeKind.highlighter);
      expect(stroke.highlighterOpacity, .35);
      expect(stroke.style.width, 24);
      c.setTool(EditorTool.segmentEraser);
      await editor.drag(tester, const Offset(300, 210), const Offset(300, 290));
      expect(c.elementCount, 2);
      for (final e in c.session.document.elements) {
        final s = e.content as StrokeElementContent;
        expect(s.kind, StrokeKind.highlighter);
        expect(s.highlighterOpacity, .35);
      }
      c.undo();
      expect(c.elementCount, 1);
      await tester.pumpAndSettle();
      final expected = DocumentCodec.encode(c.session.document);
      await workspace.restart(tester, store);
      expect(
        DocumentCodec.encode(workspace.canvas(tester).session.document),
        expected,
      );
      final reopened = workspace.canvas(tester);
      final snapshot = (await store.readBoard(reopened.session.document.id))!;
      final bytes = await exportPortableProject(snapshot, store);
      expect(
        DocumentCodec.encode(decodePortableProject(bytes).snapshot.document),
        expected,
      );
      await tester.runAsync(() async {
        final png = await renderBoardPng(
          document: reopened.session.document,
          store: store,
          bounds: Bounds2(0, 0, 400, 300),
          width: 800,
          height: 800,
        );
        final codec = await ui.instantiateImageCodec(png);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 800);
        expect(image.height, 800);
        image.dispose();
        codec.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Arrow menu produces reversed both-head geometry and style edits are one undo',
    (tester) async {
      await editor.open(tester);
      final c = editor.controller(tester);
      await tester.tap(find.byTooltip('Shapes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrow (A)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Drawing style'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Both ends').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await editor.drag(tester, const Offset(500, 300), const Offset(250, 200));
      final arrow = c.session.document.elements.single;
      expect((arrow.content as ArrowElementContent).heads, ArrowHeadStyle.both);
      c.setTool(EditorTool.select);
      c.selectAll();
      await tester.pump();
      await tester.tap(find.byTooltip('Drawing style'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == 'Stroke color (RRGGBB)',
        ),
        'FF0000',
      );
      await tester.tap(find.text('Dashed stroke'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      final updated = c.session.document.elements.single;
      expect(updated.transform, arrow.transform);
      expect((updated.content as ArrowElementContent).style.dashed, isTrue);
      expect((updated.content as ArrowElementContent).style.color, 0xffff0000);
      expect(c.session.document.revision, 2);
      c.undo();
      expect(
        (c.session.document.elements.single.content as ArrowElementContent)
            .style
            .dashed,
        isFalse,
      );
      c.redo();
      expect(
        (c.session.document.elements.single.content as ArrowElementContent)
            .heads,
        ArrowHeadStyle.both,
      );
    },
  );
  testWidgets(
    'new shape fill alpha persists and selected style cancellation is inert',
    (tester) async {
      await editor.open(tester);
      final c = editor.controller(tester);
      c.setTool(EditorTool.rectangle);
      c.applyDrawingStyle(
        strokeColor: 0xff2563eb,
        width: 6,
        opacity: .5,
        fill: 0x8000ff00,
        dash: true,
        heads: ArrowHeadStyle.end,
        markerOpacity: .35,
      );
      await editor.drag(tester, const Offset(200, 200), const Offset(400, 300));
      final content =
          c.session.document.elements.single.content as ShapeElementContent;
      expect(content.fillColor, 0x8000ff00);
      expect(content.stroke!.color >>> 24, 128);
      expect(content.stroke!.dashed, isTrue);
      c.setTool(EditorTool.select);
      c.selectAll();
      await tester.pump();
      final before = c.session.document;
      await tester.tap(find.byTooltip('Drawing style'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.session.document, same(before));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'phone exposes highlighter and touch transition cancels drawing draft',
    (tester) async {
      await editor.open(tester, size: const Size(390, 844));
      final c = editor.controller(tester);
      await tester.tap(find.byTooltip('More tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Highlighter (M)'));
      await tester.pumpAndSettle();
      final origin = editor.canvasOrigin(tester);
      final first = await tester.startGesture(origin + const Offset(130, 200));
      await first.moveTo(origin + const Offset(200, 230));
      final second = await tester.startGesture(origin + const Offset(250, 300));
      await second.moveTo(origin + const Offset(270, 320));
      await first.up();
      await second.up();
      await tester.pump();
      expect(c.elementCount, 0);
      expect(c.previewPath, isNull);
    },
  );
  test(
    'mixed drawing tools round trip with original image and render 4K without changing data',
    () async {
      final document = drawingToolsFixture();
      final encoded = DocumentCodec.encode(document);
      final store = TestBoardStore()..assets['drawing-image'] = imageTestPng();
      final snapshot = BoardSnapshot(
        document: document,
        camera: Camera(),
        version: 1,
        savedAt: DateTime.utc(2026, 10, 21),
      );
      final project = decodePortableProject(
        await exportPortableProject(snapshot, store),
      );
      expect(DocumentCodec.encode(project.snapshot.document), encoded);
      expect(project.assets['drawing-image'], imageTestPng());
      final png = await renderBoardPng(
        document: document,
        store: store,
        bounds: Bounds2(0, 0, 600, 400),
        frameId: ElementId('frame'),
        width: 3840,
        height: 2160,
        backgroundColor: 0xffffffff,
      );
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      expect((image.width, image.height), (3840, 2160));
      image.dispose();
      codec.dispose();
      expect(DocumentCodec.encode(document), encoded);
    },
  );
}
