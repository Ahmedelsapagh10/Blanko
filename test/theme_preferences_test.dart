import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/main.dart';
import 'package:whiteboard/src/theme/blanko_brand.dart';
import 'package:whiteboard/src/theme/open_theme_preference_store.dart'
    show openThemePreferenceStore;
import 'package:whiteboard/src/theme/theme_preference_store.dart';
import 'package:whiteboard/src/theme/theme_settings.dart';

import 'support/test_board_store.dart';

class _Store implements ThemePreferenceStore {
  String? value;
  bool fail = false;
  Completer<void>? gate;
  final writes = <String>[];

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    writes.add(value);
    await gate?.future;
    if (fail) throw StateError('Storage unavailable');
    this.value = value;
  }
}

class _LoadingStore extends _Store {
  final loading = Completer<String?>();

  @override
  Future<String?> read() => loading.future;
}

void main() {
  test('late preference read cannot overwrite a newer choice', () async {
    final store = _LoadingStore();
    final controller = ThemeSettingsController(store);
    final loading = controller.load();
    await controller.select(ThemeMode.dark);
    store.loading.complete('light');
    await loading;
    expect(controller.mode, ThemeMode.dark);
    expect(controller.savedMode, ThemeMode.dark);
    controller.dispose();
  });

  test('browser store reopens actual localStorage preference', () async {
    final store = openThemePreferenceStore();
    final original = await store.read();
    try {
      await store.write('dark');
      expect(await openThemePreferenceStore().read(), 'dark');
      await store.write('light');
      expect(await openThemePreferenceStore().read(), 'light');
    } finally {
      await store.write(original ?? 'system');
    }
  }, skip: !kIsWeb);

  test('choice reopens and rapid writes remain serialized', () async {
    final store = _Store()..gate = Completer<void>();
    final controller = ThemeSettingsController(store);
    await controller.load();
    final dark = controller.select(ThemeMode.dark);
    final light = controller.select(ThemeMode.light);
    final system = controller.select(ThemeMode.system);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, ['dark']);
    expect(controller.mode, ThemeMode.system);
    expect(controller.saving, isTrue);
    store.gate!.complete();
    await Future.wait([dark, light, system]);
    expect(store.writes, ['dark', 'light', 'system']);
    expect(controller.savedMode, ThemeMode.system);
    expect(controller.saving, isFalse);
    final reopened = ThemeSettingsController(store);
    await reopened.load();
    expect(reopened.mode, ThemeMode.system);
    await reopened.select(ThemeMode.dark);
    final again = ThemeSettingsController(store);
    await again.load();
    expect(again.mode, ThemeMode.dark);
    controller.dispose();
    reopened.dispose();
    again.dispose();
  });

  test(
    'failure preserves chosen mode without claiming saved and retries',
    () async {
      final store = _Store();
      final controller = ThemeSettingsController(store);
      await controller.load();
      store.fail = true;
      await controller.select(ThemeMode.dark);
      expect(controller.mode, ThemeMode.dark);
      expect(controller.savedMode, ThemeMode.system);
      expect(controller.error, contains('could not be saved'));
      expect(controller.saving, isFalse);
      store.fail = false;
      await controller.retry();
      expect(controller.error, isNull);
      expect(controller.savedMode, ThemeMode.dark);
      expect(store.value, 'dark');
      controller.dispose();
    },
  );

  test('invalid stored choice reports failure and uses system', () async {
    final controller = ThemeSettingsController(_Store()..value = 'unknown');
    await controller.load();
    expect(controller.mode, ThemeMode.system);
    expect(controller.savedMode, isNull);
    expect(controller.error, contains('Could not read'));
    controller.dispose();
  });

  test(
    'pending write after disposal cannot notify disposed controller',
    () async {
      final store = _Store()..gate = Completer<void>();
      final controller = ThemeSettingsController(store);
      final writing = controller.select(ThemeMode.dark);
      controller.dispose();
      store.gate!.complete();
      await writing;
      expect(store.value, 'dark');
    },
  );

  testWidgets('entry restores injected appearance independently from boards', (
    tester,
  ) async {
    await tester.pumpWidget(
      WhiteboardApp(
        store: TestBoardStore(),
        themeStore: _Store()..value = 'dark',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.text('Saved locally'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('appearance menu chooses all modes and system follows device', (
    tester,
  ) async {
    final controller = ThemeSettingsController(_Store());
    addTearDown(controller.dispose);
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    Widget host() => ThemeSettingsScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => MaterialApp(
          theme: BlankoTheme.light,
          darkTheme: BlankoTheme.dark,
          themeMode: controller.mode,
          home: Scaffold(
            appBar: AppBar(actions: const [ThemeSettingsButton()]),
            body: Builder(
              builder: (context) => Text(Theme.of(context).brightness.name),
            ),
          ),
        ),
      ),
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('light'), findsOneWidget);
    for (final choice in ['Dark', 'Light', 'System']) {
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<ThemeMode> &&
              widget.value?.name == choice.toLowerCase(),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.mode.name, choice.toLowerCase());
    }
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpAndSettle();
    expect(find.text('dark'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'isolated hosts safely show appearance without persistence scope',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ThemeSettingsButton())),
      );
      expect(find.byTooltip('Appearance'), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuButton<ThemeMode>>(
              find.byType(PopupMenuButton<ThemeMode>),
            )
            .enabled,
        isFalse,
      );
    },
  );
}
