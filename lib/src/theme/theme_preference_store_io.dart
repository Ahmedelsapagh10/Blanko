import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'theme_preference_store.dart';

ThemePreferenceStore openThemePreferenceStore() => FileThemePreferenceStore();

class FileThemePreferenceStore implements ThemePreferenceStore {
  FileThemePreferenceStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  Future<void> _writes = Future<void>.value();

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File('${directory.path}/appearance-v1.txt');
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    return await file.exists() ? (await file.readAsString()).trim() : null;
  }

  @override
  Future<void> write(String value) {
    final operation = _writes.then((_) async {
      final file = await _file();
      final temporary = File('${file.path}.tmp-$pid');
      try {
        await temporary.writeAsString(value, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
