import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/advanced_editor_actions.dart';
import 'package:whiteboard/src/editor/board_session.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/editor_page.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'advanced_editor_test.dart' as advanced;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final menuCalls = <String>[];
  if (kIsWeb) {
    // Widget tests exercise ordered channel ownership; real Chrome right-click
    // is verified separately in the running application.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.contextMenu, (call) async {
          menuCalls.add(call.method);
          return null;
        });
  }

  testWidgets('Editor owns browser context menu and restores it on exit', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pumpAndSettle();
    expect(BrowserContextMenu.enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(BrowserContextMenu.enabled, isTrue);
    expect(menuCalls.last, 'enableContextMenu');
  }, skip: !kIsWeb);

  testWidgets('rapid Editor replacement retains browser menu ownership', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: EditorPage(key: ValueKey(1))),
    );
    await tester.pumpWidget(
      const MaterialApp(home: EditorPage(key: ValueKey(2))),
    );
    await tester.pumpAndSettle();
    expect(BrowserContextMenu.enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(BrowserContextMenu.enabled, isTrue);
    expect(menuCalls.last, 'enableContextMenu');
  }, skip: !kIsWeb);

  testWidgets(
    'touch multi-select is discoverable and toggles without a keyboard',
    (tester) async {
      final c = await advanced.setup(tester);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tool properties'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Touch multi-select'));
      await tester.pumpAndSettle();
      expect(c.multiSelectMode, isTrue);
      final toggle = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Touch multi-select',
        ),
      );
      expect(toggle.isSelected, isTrue);
      // Dismiss only the properties sheet, retaining its chosen mode.
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      // The mobile viewport cannot display the second setup rectangle at x400.
      c.resetCamera();
      c.zoom(.5, const Offset(0, 0));
      await tester.pump();
      for (final id in c.session.document.byId.keys) {
        final p = c.camera.worldToViewport(c.scene.boundsOf(id).center);
        await advanced.click(tester, Offset(p.x, p.y));
      }
      expect(c.selectedIds, hasLength(2));
      expect(c.session.document.revision, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('group editing has a direct exit and inherited lock indication', (
    tester,
  ) async {
    final c = await advanced.setup(tester);
    c.selectAll();
    c.groupSelection();
    final group = c.selectedId!;
    c.enterGroup();
    await tester.pump();
    expect(find.text('Exit group'), findsOneWidget);
    await tester.tap(find.text('Exit group'));
    await tester.pump();
    expect(c.editingGroupId, isNull);
    c.enterGroup(); // No selection means no accidental re-entry.
    expect(c.editingGroupId, isNull);
    final child = c.session.document.childrenOf(group).first.id;
    c.selectedId = child;
    c.lockSelection(true);
    c.selectedId = group;
    c.setTool(EditorTool.select);
    await tester.pump();
    expect(
      find.byTooltip(
        'Selection or its contents are locked. Use Locked items to unlock.',
      ),
      findsOneWidget,
    );
    expect(c.canEditSelection, isFalse);
    final before = c.session.document;
    c.deleteSelection();
    expect(c.session.document, same(before));
  });

  testWidgets('incompatible owners disable alignment and distribution safely', (
    tester,
  ) async {
    final frame = ElementId('frame'), a = ElementId('a'), b = ElementId('b');
    ShapeElementContent shape(double x) => ShapeElementContent(
      kind: ShapeKind.rectangle,
      bounds: Bounds2(x, 200, x + 20, 220),
      fillColor: 0xff2563eb,
    );
    final c = EditorCanvasController(
      session: BoardSession(
        document: BoardDocument(
          id: 'parents',
          revision: 0,
          elements: [
            DocumentElement(
              id: frame,
              content: ContainerFrameElementContent(
                bounds: Bounds2(0, 0, 100, 100),
                label: 'Frame',
              ),
            ),
            DocumentElement(id: a, parentId: frame, content: shape(0)),
            DocumentElement(id: b, content: shape(200)),
          ],
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: c)));
    addTearDown(c.dispose);
    c.selectedId = a;
    c.multiSelectMode = true;
    c.setTool(EditorTool.select);
    final p = c.camera.worldToViewport(c.scene.boundsOf(b).center);
    await advanced.click(tester, Offset(p.x, p.y));
    expect(c.selectedIds, hasLength(2));
    final entries = AdvancedEditorActions.entries(
      c,
    ).whereType<PopupMenuItem<String>>();
    for (final action in ['align-left', 'distribute-h', 'group']) {
      expect(entries.singleWhere((e) => e.value == action).enabled, isFalse);
    }
    final before = c.session.document;
    c.layoutSelection('align-left');
    expect(c.session.document, same(before));
    expect(c.message, contains('same frame or group'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
