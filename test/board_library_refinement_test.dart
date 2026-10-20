import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/editor_page.dart';

import 'board_library_ui_test.dart' as helpers;
import 'support/test_board_store.dart';

void main() {
  testWidgets('search filters by name and recovers from no results', (
    tester,
  ) async {
    final store = TestBoardStore();
    await helpers.openLibrary(tester, store);
    await helpers.menu(tester, 'Rename');
    await tester.enterText(
      find.byKey(const ValueKey('rename-board-input')),
      'Ideas',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-rename-board')));
    await tester.pumpAndSettle();
    await helpers.menu(tester, 'Duplicate');
    await tester.tap(find.byTooltip('Search boards'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('board-search-input'));
    await tester.enterText(search, ' COPY ');
    await tester.pumpAndSettle();
    expect(find.text('Ideas (Copy)'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Ideas')),
      findsNothing,
    );
    await tester.enterText(search, 'unmatched');
    await tester.pumpAndSettle();
    expect(find.text('No matching boards'), findsOneWidget);
    expect(store.records.length, 2);
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Ideas')),
      findsOneWidget,
    );
    expect(find.text('Ideas (Copy)'), findsOneWidget);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(search, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'header rename uses session and persists without switching boards',
    (tester) async {
      final store = TestBoardStore();
      await helpers.openLibrary(tester, store);
      await tester.tap(find.byTooltip('Close board history'));
      await tester.pumpAndSettle();
      final id = helpers.canvas(tester).session.document.id;
      tester.widget<EditorPage>(find.byType(EditorPage)).onRenameBoard!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('rename-board-input')),
        'Project plan',
      );
      await tester.tap(find.byKey(const ValueKey('confirm-rename-board')));
      await tester.pumpAndSettle();
      expect(helpers.canvas(tester).session.document.id, id);
      expect(helpers.canvas(tester).session.document.title, 'Project plan');
      expect((await store.readBoard(id))!.document.title, 'Project plan');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('phone board search has no overflow', (tester) async {
    await helpers.openLibrary(
      tester,
      TestBoardStore(),
      size: const Size(390, 844),
    );
    await tester.tap(find.byTooltip('Search boards'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('board-search-input')),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching boards'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
