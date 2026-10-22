import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/editor_page.dart';
import 'package:whiteboard/src/theme/blanko_brand.dart';
import 'support/test_board_store.dart';
import 'support/image_test_bytes.dart';
import 'workspace_widget_test.dart' as workspace;

void main() {
  testWidgets(
    'desktop more tools is an anchored menu and image import is discoverable',
    (tester) async {
      await workspace.open(tester, TestBoardStore());
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              (w.tooltip == 'Insert image' ||
                  w.tooltip ==
                      'Image import available on Android, iOS, macOS and Web'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('More tools'));
      await tester.pumpAndSettle();
      expect(find.text('Export frame'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Keyboard & gestures'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'image context exposes image actions without a dead text edit button',
    (tester) async {
      final store = TestBoardStore();
      await workspace.open(tester, store);
      final c = workspace.canvas(tester);
      await tester.runAsync(() async {
        await c.importImage(bytes: imageTestPng(), filename: 'bands.png');
      });
      await tester.pumpAndSettle();
      expect(find.text('Image'), findsOneWidget);
      expect(find.byTooltip('Edit text / resize'), findsNothing);
      expect(find.byTooltip('Rotate 90° (⌘/Ctrl R)'), findsOneWidget);
      expect(find.text('Saved locally'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow phone supports scaled labels, properties and image errors',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = EditorCanvasController();
      addTearDown(c.dispose);
      c.imageCache.errors['missing'] = 'Original image is missing';
      c.message = 'Image unavailable. Restore the asset and use Retry images.';
      await tester.pumpWidget(
        MaterialApp(
          theme: BlankoTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.5),
            ),
            child: EditorPage(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry images'), findsOneWidget);
      await tester.tap(find.byTooltip('Tool properties'));
      await tester.pumpAndSettle();
      expect(find.text('Medium'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
