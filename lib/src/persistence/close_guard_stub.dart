final class UnsavedCloseGuard {
  UnsavedCloseGuard(bool Function() isDirty);
  void dispose() {}
}
