@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/main.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/inline_text_editor.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/theme/theme_preference_store.dart';
import 'support/test_board_store.dart';

class _Appearance implements ThemePreferenceStore {
  _Appearance(this.mode);
  String mode;
  @override
  Future<String?> read() async => mode;
  @override
  Future<void> write(String value) async {
    mode = value;
  }
}

Future<void> main() async {
  // Widget tests substitute Ahem for unavailable families. Match the app's
  // bundled Roboto fallback and load real Material glyphs for visual artifacts.
  if (Platform.environment['BLANKO_CAPTURE_UI'] == '1') {
    for (final font in const {
      'Inter': 'assets/benchmark_fonts/Roboto-Regular.ttf',
      'Roboto': 'assets/benchmark_fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  }

  testWidgets('capture real Flutter phone and tablet presentation', (
    tester,
  ) async {
    if (Platform.environment['BLANKO_CAPTURE_UI'] != '1') return;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(390, 844), const Size(834, 1112)]) {
      for (final mode in ['dark', 'light']) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture'),
            child: WhiteboardApp(
              store: TestBoardStore(),
              themeStore: _Appearance(mode),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final c = tester
            .widget<EditorCanvas>(find.byType(EditorCanvas))
            .controller;
        c.saveText(
          TextElementContent(
            text: 'Ideas take shape.\nمساحة لأفكارك',
            bounds: Bounds2(0, 0, 260, 100),
            style: ElementTextStyle(
              fontId: 'editor-sans-v1',
              fontSize: 24,
              color: 0xff202d46,
            ),
          ),
          Point2(0, 80),
        );
        c.saveText(
          StickyNoteElementContent(
            text: 'Sketch. Think. Create.\nStart with one idea.',
            bounds: Bounds2(0, 0, 240, 180),
            backgroundColor: 0xffd9edff,
            style: ElementTextStyle(
              fontId: 'editor-sans-v1',
              fontSize: 22,
              color: 0xff202d46,
            ),
          ),
          Point2(0, 220),
        );
        c.setTool(EditorTool.pen);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          '${size.width < 700 ? 'phone' : 'tablet'}-$mode',
        );
        if (mode == 'dark') {
          c.setTool(EditorTool.sticky);
          final origin = tester.getTopLeft(
            find.byKey(const ValueKey('board-canvas')),
          );
          await tester.tapAt(origin + const Offset(150, 200));
          await tester.pumpAndSettle();
          final draft = tester
              .widget<InlineTextLayer>(find.byType(InlineTextLayer))
              .draft;
          const text = 'Ideas stay readable.\nأفكار واضحة';
          draft.editor.replaceText(
            0,
            draft.editor.document.length - 1,
            text,
            const TextSelection.collapsed(offset: text.length),
          );
          await tester.pumpAndSettle();
          await _capture(
            tester,
            '${size.width < 700 ? 'phone' : 'tablet'}-text-dark',
          );
          await tester.ensureVisible(find.byTooltip('Cancel text editing'));
          await tester.tap(find.byTooltip('Cancel text editing'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File(
        '${Platform.environment['BLANKO_UI_CAPTURE_DIR'] ?? 'benchmark_results/ui-ux'}/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}
