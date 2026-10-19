import 'dart:convert';
import 'dart:ui_web' as web;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/benchmarks/benchmark_fonts.dart';

void configureFontAssets() {
  web.TestEnvironment.setUp(
    const web.TestEnvironment(
      ignorePlatformMessages: true,
      forceTestFonts: false,
      disableFontFallbacks: true,
      keepSemanticsDisabledOnUpdate: true,
      defaultToTestUrlStrategy: true,
    ),
  );
  final assets = web.AssetManager(assetsDir: 'benchmark_font_assets');
  final allowed = BenchmarkFonts.assets.values.expand((paths) => paths).toSet();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        if (!allowed.contains(key)) return null;
        // Generated from verified originals by verify_benchmark_fonts.py
        // --prepare-web-tests; the SDK browser runner serves test/ as its root.
        return assets.load(key.split('/').last);
      });
}
