import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/main.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/viewport/camera.dart';

import 'support/test_board_store.dart';

EditorCanvasController canvas(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).controller;
Future<void> open(WidgetTester tester, TestBoardStore store) async {
  tester.view.physicalSize = const Size(1200, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(WhiteboardApp(store: store));
  await tester.pumpAndSettle();
}

Future<void> pen(WidgetTester tester, [double x = 100]) async {
  final origin = tester.getTopLeft(find.byKey(const ValueKey('board-canvas')));
  final pointer = await tester.startGesture(
    origin + Offset(x, 100),
    kind: PointerDeviceKind.mouse,
  );
  await pointer.moveTo(origin + Offset(x + 100, 160));
  await pointer.up();
  await tester.pump();
}

Future<void> restart(WidgetTester tester, TestBoardStore store) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.pumpWidget(WhiteboardApp(store: store));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'completed drawing persists and simulated widget reopening resets undo only',
    (tester) async {
      final store = TestBoardStore();
      await open(tester, store);
      await pen(tester);
      await tester.pumpAndSettle();
      final before = canvas(tester).session.document;
      expect(find.text('Saved locally'), findsOneWidget);
      expect(
        (await store.readBoard(before.id))!.document.elements,
        hasLength(1),
      );
      await restart(tester, store);
      final after = canvas(tester).session.document;
      expect(after.id, before.id);
      expect(after.revision, before.revision);
      expect(after.elements.single.transform, before.elements.single.transform);
      expect(canvas(tester).session.canUndo, isFalse);
      expect(find.text('Saved locally'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rapid edits and undo wait for latest acknowledged snapshot', (
    tester,
  ) async {
    final store = TestBoardStore();
    await open(tester, store);
    final gate = store.writeGate = Completer<void>();
    await pen(tester);
    await pen(tester, 300);
    await tester.tap(find.byTooltip('Undo (⌘/Ctrl Z)'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(canvas(tester).elementCount, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Saved locally'), findsOneWidget);
    await restart(tester, store);
    expect(canvas(tester).elementCount, 1);
    expect(canvas(tester).session.document.revision, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('library creates independent boards and last board reopens', (
    tester,
  ) async {
    final store = TestBoardStore();
    await open(tester, store);
    await pen(tester);
    await tester.pumpAndSettle();
    final first = canvas(tester).session.document.id;
    await tester.tap(find.byTooltip('Boards'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Second board');
    await tester.tap(find.text('Create board'));
    await tester.pumpAndSettle();
    expect(canvas(tester).elementCount, 0);
    await pen(tester, 300);
    await pen(tester, 500);
    await tester.pumpAndSettle();
    final second = canvas(tester).session.document.id;
    expect(second, isNot(first));
    await restart(tester, store);
    expect(canvas(tester).session.document.id, second);
    expect(canvas(tester).elementCount, 2);
    await tester.tap(find.byTooltip('Boards'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Untitled board'));
    await tester.pumpAndSettle();
    expect(canvas(tester).session.document.id, first);
    expect(canvas(tester).elementCount, 1);
    expect(store.last, first);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed save retains work, blocks board switch and retries', (
    tester,
  ) async {
    final store = TestBoardStore();
    await open(tester, store);
    final id = store.last!;
    store.failWrites = true;
    await pen(tester);
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsOneWidget);
    expect(canvas(tester).elementCount, 1);
    expect((await store.readBoard(id))!.document.elements, isEmpty);
    await tester.tap(find.byTooltip('Boards'));
    await tester.pumpAndSettle();
    expect(find.text('Create board'), findsNothing);
    expect(canvas(tester).session.document.id, id);
    store.failWrites = false;
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved locally'), findsOneWidget);
    expect((await store.readBoard(id))!.document.elements, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending switch disables keyboard editing until save completes', (
    tester,
  ) async {
    final store = TestBoardStore();
    await open(tester, store);
    final gate = store.writeGate = Completer<void>();
    await pen(tester);
    await tester.tap(find.byTooltip('Boards'));
    await tester.pump();
    expect(find.text('Create board'), findsNothing);
    expect(canvas(tester).inputEnabled, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(canvas(tester).elementCount, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Create board'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Saved locally'), findsOneWidget);
    expect(canvas(tester).inputEnabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native exit awaits pending write and cancels failed saves', (
    tester,
  ) async {
    final store = TestBoardStore();
    await open(tester, store);
    final gate = store.writeGate = Completer<void>();
    await pen(tester);
    var completed = false;
    final exit = tester.binding.handleRequestAppExit().then((value) {
      completed = true;
      return value;
    });
    await tester.pump();
    expect(completed, isFalse);
    gate.complete();
    await tester.pumpAndSettle();
    expect(await exit, AppExitResponse.exit);
    store.failWrites = true;
    await pen(tester, 300);
    await tester.pumpAndSettle();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    store.failWrites = false;
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read only secondary cannot author or save changes', (
    tester,
  ) async {
    final store = TestBoardStore()..readOnly = true;
    final snapshot = BoardSnapshot(
      document: BoardDocument(
        id: 'existing',
        title: 'Existing board',
        revision: 0,
        elements: [],
        assets: [],
        fontReferences: [],
      ),
      camera: Camera(),
      version: 1,
      savedAt: DateTime.utc(2026),
    );
    store.records['existing'] = snapshot.encode();
    store.last = 'existing';
    await open(tester, store);
    expect(find.text('Read only · another window is editing'), findsOneWidget);
    await pen(tester);
    expect(canvas(tester).elementCount, 0);
    expect(store.writes, 0);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'storage initialization failure never falls back to empty editable memory',
    (tester) async {
      final store = TestBoardStore()..failInitialize = true;
      await open(tester, store);
      expect(find.byType(EditorCanvas), findsNothing);
      expect(find.textContaining('Storage unavailable'), findsOneWidget);
      store.failInitialize = false;
      await tester.tap(find.text('Retry opening local boards'));
      await tester.pumpAndSettle();
      expect(find.byType(EditorCanvas), findsOneWidget);
      expect(find.text('Saved locally'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('lost writer retains edits and cancels application exit', (
    tester,
  ) async {
    final store = TestBoardStore();
    await open(tester, store);
    store.readOnly = true;
    await pen(tester);
    await tester.pumpAndSettle();
    expect(canvas(tester).elementCount, 1);
    expect(find.text('Save failed'), findsOneWidget);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await tester.tap(find.byTooltip('Boards'));
    await tester.pumpAndSettle();
    expect(find.text('Create board'), findsNothing);
    store.readOnly = false;
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved locally'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening cleanup failure retains original error and retry', (
    tester,
  ) async {
    final store = TestBoardStore()
      ..failInitialize = true
      ..failClose = true;
    await open(tester, store);
    expect(find.textContaining('Storage unavailable'), findsOneWidget);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(find.textContaining('Close denied'), findsOneWidget);
    expect(find.byType(EditorCanvas), findsNothing);
    store.failInitialize = store.failClose = false;
    await tester.tap(find.text('Retry opening local boards'));
    await tester.pumpAndSettle();
    expect(find.text('Saved locally'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('viewport-only changes are acknowledged and restored', (
    tester,
  ) async {
    final store = TestBoardStore();
    await open(tester, store);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final before = canvas(tester).camera;
    expect(find.text('Saved locally'), findsOneWidget);
    await restart(tester, store);
    expect(canvas(tester).camera.zoom, before.zoom);
    expect(canvas(tester).camera.translation, before.translation);
    expect(canvas(tester).session.document.revision, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'disposing during storage opening cannot create a stale default board',
    (tester) async {
      final gate = Completer<void>();
      final store = TestBoardStore()..initializeGate = gate;
      await tester.pumpWidget(WhiteboardApp(store: store));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(store.records, isEmpty);
      expect(store.writes, 0);
      expect(store.closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
