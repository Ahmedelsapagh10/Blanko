import 'package:flutter/material.dart';

import 'src/editor/workspace_page.dart';
import 'src/persistence/board_store.dart';
import 'src/theme/blanko_brand.dart';
import 'src/theme/open_theme_preference_store.dart'
    show openThemePreferenceStore;
import 'src/theme/theme_preference_store.dart';
import 'src/theme/theme_preference_store_stub.dart'
    show UnavailableThemePreferenceStore;
import 'src/theme/theme_settings.dart';

void main() => runApp(const WhiteboardApp());

class WhiteboardApp extends StatefulWidget {
  const WhiteboardApp({super.key, this.store, this.themeStore});
  final BoardStore? store;
  final ThemePreferenceStore? themeStore;

  @override
  State<WhiteboardApp> createState() => _WhiteboardAppState();
}

class _WhiteboardAppState extends State<WhiteboardApp> {
  late final ThemeSettingsController _appearance;

  @override
  void initState() {
    super.initState();
    _appearance = ThemeSettingsController(
      widget.themeStore ??
          (widget.store == null
              ? openThemePreferenceStore()
              : const UnavailableThemePreferenceStore()),
    );
    _appearance.load();
  }

  @override
  void dispose() {
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ThemeSettingsScope(
    controller: _appearance,
    child: ListenableBuilder(
      listenable: _appearance,
      builder: (context, _) => MaterialApp(
        title: BlankoBrand.appName,
        debugShowCheckedModeBanner: false,
        theme: BlankoTheme.light,
        darkTheme: BlankoTheme.dark,
        themeMode: _appearance.mode,
        themeAnimationDuration:
            WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 160),
        home: WorkspacePage(store: widget.store),
      ),
    ),
  );
}
