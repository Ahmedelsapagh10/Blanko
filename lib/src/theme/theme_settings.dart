import 'package:flutter/material.dart';

import 'theme_preference_store.dart';

class ThemeSettingsController extends ChangeNotifier {
  ThemeSettingsController(this.store);

  final ThemePreferenceStore store;
  ThemeMode mode = ThemeMode.system;
  ThemeMode? savedMode;
  String? error;
  bool saving = false;
  bool _disposed = false;
  int _generation = 0;
  Future<void> _writes = Future<void>.value();

  Future<void> load() async {
    final generation = _generation;
    try {
      final value = await store.read();
      final selected = value == null
          ? ThemeMode.system
          : ThemeMode.values.firstWhere((mode) => mode.name == value);
      if (_disposed || generation != _generation) return;
      mode = selected;
      savedMode = selected;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = 'Could not read appearance. Using system appearance.';
    }
    notifyListeners();
  }

  Future<void> select(ThemeMode value) {
    if (_disposed) return Future<void>.value();
    final generation = ++_generation;
    mode = value;
    saving = true;
    error = null;
    notifyListeners();
    final operation = _writes.then((_) async {
      try {
        await store.write(value.name);
        if (_disposed) return;
        savedMode = value;
        if (generation == _generation) error = null;
      } catch (_) {
        if (_disposed) return;
        if (generation == _generation) {
          error = 'Appearance changed, but could not be saved. Please retry.';
        }
      }
      if (!_disposed && generation == _generation) {
        saving = false;
        notifyListeners();
      }
    });
    _writes = operation;
    return operation;
  }

  Future<void> retry() => select(mode);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ThemeSettingsScope extends InheritedNotifier<ThemeSettingsController> {
  const ThemeSettingsScope({
    super.key,
    required ThemeSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeSettingsController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ThemeSettingsScope>()
      ?.notifier;
}

class ThemeSettingsButton extends StatelessWidget {
  const ThemeSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeSettingsScope.maybeOf(context);
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      enabled: controller != null,
      icon: Icon(
        controller?.mode == ThemeMode.dark
            ? Icons.dark_mode_outlined
            : controller?.mode == ThemeMode.light
            ? Icons.light_mode_outlined
            : Icons.brightness_auto_outlined,
      ),
      initialValue: controller?.mode,
      onSelected: (mode) async {
        await controller!.select(mode);
        if (!context.mounted || controller.error == null) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(controller.error!),
            action: SnackBarAction(label: 'Retry', onPressed: controller.retry),
          ),
        );
      },
      itemBuilder: (_) => [
        for (final item in const [
          (ThemeMode.system, Icons.brightness_auto_outlined, 'System'),
          (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
          (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
        ])
          CheckedPopupMenuItem(
            value: item.$1,
            checked: controller?.mode == item.$1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$2, size: 20),
                const SizedBox(width: 12),
                Text(item.$3),
              ],
            ),
          ),
        if (controller?.error != null)
          const PopupMenuItem(
            enabled: false,
            child: Text('Not saved · choose again to retry'),
          ),
      ],
    );
  }
}
