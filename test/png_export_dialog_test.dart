import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/editor_page.dart';
import 'package:whiteboard/src/editor/png_export_dialog.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/theme/blanko_brand.dart';

import 'support/test_board_store.dart';

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
String _value(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<EditorCanvasController> _open(
  WidgetTester tester,
  TestBoardStore store, {
  bool frame = false,
  bool phone = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1200, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = BoardSession(
    document: BoardDocument(
      id: 'export-dialog',
      title: 'Dialog artwork',
      revision: 0,
      elements: const [],
      assets: const [],
      fontReferences: const [],
    ),
  );
  ElementId? frameId;
  if (frame) {
    frameId = session.insert(
      ExportFrameElementContent(
        bounds: Bounds2(0, 0, 320, 180),
        label: 'Presentation لوحة',
        outputWidth: 1280,
        outputHeight: 720,
      ),
      transform: Transform2.translation(50, 80),
    );
  }
  final c = EditorCanvasController(session: session, store: store)
    ..setTool(EditorTool.select)
    ..selectedId = frameId;
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: phone ? BlankoTheme.dark : BlankoTheme.light,
      home: EditorPage(controller: c),
    ),
  );
  await tester.pump();
  expect(
    tester.takeException(),
    isNull,
    reason: 'Editor shell before PNG dialog',
  );
  return c;
}

Future<void> _dialog(WidgetTester tester, EditorCanvasController c) async {
  final context = tester.element(find.byType(EditorPage));
  showPngExportDialog(context, c);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'PNG dialog initial layout');
}

void main() {
  testWidgets(
    'PNG dialog defaults to selected frame, presets and viewport; closing preserves board',
    (tester) async {
      final store = TestBoardStore();
      final c = await _open(tester, store, frame: true);
      final before = c.session.document;
      final selected = c.selectedId;
      await _dialog(tester, c);
      expect(_value(tester, 'Width (px)'), '1280');
      expect(_value(tester, 'Height (px)'), '720');
      await tester.tap(find.widgetWithText(ActionChip, '4K'));
      await tester.pump();
      expect(_value(tester, 'Width (px)'), '3840');
      expect(_value(tester, 'Height (px)'), '2160');
      await tester.tap(find.text('Transparent background'));
      await tester.pump();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Current viewport').last);
      await tester.pumpAndSettle();
      final viewport = c.camera.worldViewport(
        c.viewportSize.width,
        c.viewportSize.height,
      );
      expect(_value(tester, 'Width (px)'), '${viewport.width.round()}');
      expect(_value(tester, 'Height (px)'), '${viewport.height.round()}');
      await tester.tap(find.widgetWithText(ActionChip, 'HD'));
      await tester.pump();
      expect(_value(tester, 'Width (px)'), '1920');
      expect(_value(tester, 'Height (px)'), '1080');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(c.session.document, same(before));
      expect(c.selectedId, selected);
      expect(store.writes, 0);
      expect(store.assets, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'phone dark PNG dialog validates limits without saving or overflow',
    (tester) async {
      final store = TestBoardStore();
      final c = await _open(tester, store, phone: true);
      final before = c.session.document;
      await _dialog(tester, c);
      for (final dimensions in [
        ('0', '200'),
        ('8193', '1'),
        ('8192', '8192'),
        ('wide', '200'),
      ]) {
        await tester.enterText(_field('Width (px)'), dimensions.$1);
        await tester.enterText(_field('Height (px)'), dimensions.$2);
        await tester.tap(find.widgetWithText(FilledButton, 'Export PNG'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Use positive dimensions'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(c.session.document, same(before));
        expect(store.writes, 0);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(c.session.document, same(before));
      expect(store.assets, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'macOS PNG dialog sends actual PNG bytes to native save gateway',
    (tester) async {
      final store = TestBoardStore();
      final c = await _open(tester, store, frame: true);
      final before = c.session.document;
      Uint8List? captured;
      var calls = 0;
      const channel = MethodChannel('blanko/project_files');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveFile');
        final arguments = call.arguments as Map;
        expect(arguments['extension'], 'png');
        expect(arguments['suggestedName'], 'Dialog artwork');
        captured = arguments['bytes'] as Uint8List;
        calls++;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _dialog(tester, c);
      await tester.enterText(_field('Width (px)'), '64');
      await tester.enterText(_field('Height (px)'), '36');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Export PNG'));
        for (var i = 0; i < 100 && captured == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(captured, isNotNull);
      expect(captured!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(captured!);
        try {
          final image = (await codec.getNextFrame()).image;
          try {
            expect(image.width, 64);
            expect(image.height, 36);
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }
      });
      expect(find.text('Export complete'), findsOneWidget);
      expect(find.text('PNG saved.'), findsOneWidget);
      expect(_field('Width (px)'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Export PNG'), findsNothing);
      expect(c.session.document, same(before));
      expect(store.writes, 0);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip: kIsWeb,
  );

  testWidgets(
    'native save cancellation or failure keeps export settings open',
    (tester) async {
      const channel = MethodChannel('blanko/project_files');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final c = await _open(tester, TestBoardStore());
      for (final fail in [false, true]) {
        var called = false;
        messenger.setMockMethodCallHandler(channel, (_) async {
          called = true;
          if (fail) {
            throw PlatformException(code: 'write_failed', message: 'Disk full');
          }
          return false;
        });
        await _dialog(tester, c);
        await tester.enterText(_field('Width (px)'), '64');
        await tester.enterText(_field('Height (px)'), '36');
        await tester.runAsync(() async {
          await tester.tap(find.widgetWithText(FilledButton, 'Export PNG'));
          for (var i = 0; i < 100 && !called; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();
        expect(called, isTrue);
        expect(_value(tester, 'Width (px)'), '64');
        expect(find.text('Export complete'), findsNothing);
        expect(
          find.text('Save cancelled.'),
          fail ? findsNothing : findsOneWidget,
        );
        if (fail) {
          expect(find.textContaining('Could not export PNG:'), findsOneWidget);
        }
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
    skip: kIsWeb,
  );
}
