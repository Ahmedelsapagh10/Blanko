import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_fonts.dart';

import 'support/font_assets_host.dart'
    if (dart.library.js_interop) 'support/font_assets_web.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureFontAssets();
  // Load genuine fixed fonts outside widget tests' fake clocks. Browser tests
  // otherwise ignore flutter/assets messages and force Ahem over custom fonts.
  await BenchmarkFonts.instance.ensureLoaded();
  await testMain();
}
