import 'theme_preference_store.dart';

ThemePreferenceStore openThemePreferenceStore() =>
    const UnavailableThemePreferenceStore();

class UnavailableThemePreferenceStore implements ThemePreferenceStore {
  const UnavailableThemePreferenceStore();

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async =>
      throw UnsupportedError('Appearance cannot be saved on this device.');
}
