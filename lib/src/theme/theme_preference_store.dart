/// Device appearance is intentionally separate from board content and history.
abstract interface class ThemePreferenceStore {
  Future<String?> read();
  Future<void> write(String value);
}
