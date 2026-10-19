import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Browsers cannot await an async write when a tab closes. Warn while unsaved.
final class UnsavedCloseGuard {
  UnsavedCloseGuard(bool Function() isDirty) {
    _listener = ((web.Event event) {
      if (isDirty()) {
        event.preventDefault();
        (event as web.BeforeUnloadEvent).returnValue = '';
      }
    }).toJS;
    web.window.addEventListener('beforeunload', _listener);
  }
  late final JSFunction _listener;
  void dispose() => web.window.removeEventListener('beforeunload', _listener);
}
