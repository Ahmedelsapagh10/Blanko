import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/workspace_page.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';

import 'support/test_board_store.dart';

Future<void> openLibrary(
  WidgetTester tester,
  TestBoardStore store, {
  Size size = const Size(1200, 850),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: WorkspacePage(store: store)));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Boards'));
  await tester.pumpAndSettle();
}

EditorCanvasController canvas(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).controller;

Future<void> menu(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('Board options').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'history plus immediately creates and opens an independent board',
    (tester) async {
      final store = TestBoardStore();
      await openLibrary(tester, store);
      final original = canvas(tester).session.document.id;
      expect(find.text('Board History'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Active · Saved'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('create-board-circle-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Board History'), findsNothing);
      expect(canvas(tester).session.document.id, isNot(original));
      expect(store.records.length, 2);
      expect(canvas(tester).session.document.title, 'Untitled board');
      expect(store.last, canvas(tester).session.document.id);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rename and duplicate remain persistent library operations', (
    tester,
  ) async {
    final store = TestBoardStore();
    await openLibrary(tester, store);
    await menu(tester, 'Rename');
    await tester.enterText(
      find.byKey(const ValueKey('rename-board-input')),
      'Ideas',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-rename-board')));
    await tester.pumpAndSettle();
    expect((await store.readBoard(store.last!))!.document.title, 'Ideas');
    await menu(tester, 'Duplicate');
    expect(store.records.length, 2);
    expect(find.text('Ideas (Copy)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'pending duplicate prevents repeated writes and dismissing history',
    (tester) async {
      final store = TestBoardStore();
      await openLibrary(tester, store);
      final gate = store.writeGate = Completer<void>();
      await tester.tap(find.byTooltip('Board options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pump(const Duration(milliseconds: 300));
      final create = tester.widget<IconButton>(
        find.byKey(const ValueKey('create-board-circle-btn')),
      );
      expect(create.onPressed, isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Board History'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(store.records.length, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed duplicate keeps history available and reports error', (
    tester,
  ) async {
    final store = TestBoardStore();
    await openLibrary(tester, store);
    store.failWrites = true;
    await menu(tester, 'Duplicate');
    expect(find.textContaining('Disk quota exceeded'), findsOneWidget);
    expect(store.records.length, 1);
    store.failWrites = false;
    await menu(tester, 'Duplicate');
    expect(store.records.length, 2);
    expect(
      find.textContaining('Could not complete this action.'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'delete requires confirmation and closing restores a valid board',
    (tester) async {
      final store = TestBoardStore();
      await openLibrary(tester, store);
      final original = store.last!;
      await menu(tester, 'Delete');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.records.containsKey(original), isTrue);
      await menu(tester, 'Delete');
      await tester.tap(find.byKey(const ValueKey('confirm-delete-board')));
      await tester.pumpAndSettle();
      expect(store.records.containsKey(original), isFalse);
      expect(find.text('A fresh space for your ideas'), findsOneWidget);
      await tester.tap(find.byTooltip('Close board history'));
      await tester.pumpAndSettle();
      expect(canvas(tester).session.document.id, isNot(original));
      expect(store.last, canvas(tester).session.document.id);
      expect(store.records.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mobile history stays within viewport', (tester) async {
    await openLibrary(tester, TestBoardStore(), size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(390));
    await tester.pumpWidget(const SizedBox());
  });
}
