import 'package:web/web.dart' as web;

import 'theme_preference_store.dart';

ThemePreferenceStore openThemePreferenceStore() => WebThemePreferenceStore();

class WebThemePreferenceStore implements ThemePreferenceStore {
  static const storageKey = 'blanko.appearance.v1';

  @override
  Future<String?> read() async => web.window.localStorage.getItem(storageKey);

  @override
  Future<void> write(String value) async =>
      web.window.localStorage.setItem(storageKey, value);
}
