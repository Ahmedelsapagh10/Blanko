import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Fixed laboratory fonts. Engine registrations live for the engine lifetime;
/// scene replacement must neither register again nor claim to dispose them.
final class BenchmarkFonts {
  BenchmarkFonts({AssetBundle? bundle, FontLoader Function(String)? loader})
    : _bundle = bundle ?? rootBundle,
      _loader = loader ?? FontLoader.new;

  static final instance = BenchmarkFonts();
  static const latin = 'WhiteboardBenchmarkLatin';
  static const arabic = 'WhiteboardBenchmarkArabic';
  static const manifestId = 'roboto-3.015-noto-sans-arabic-2.012-v1';
  static const assets = <String, List<String>>{
    latin: [
      'assets/benchmark_fonts/Roboto-Regular.ttf',
      'assets/benchmark_fonts/Roboto-Medium.ttf',
      'assets/benchmark_fonts/Roboto-Bold.ttf',
    ],
    arabic: ['assets/benchmark_fonts/NotoSansArabic-Regular.ttf'],
  };

  final AssetBundle _bundle;
  final FontLoader Function(String) _loader;
  final _registered = <String>{};
  Future<void>? _pending;
  bool get isReady =>
      _registered.length ==
      assets.values.fold(0, (n, paths) => n + paths.length);
  double? _registrationMs;

  Map<String, Object?> get report => {
    'manifest': manifestId,
    'ready': isReady,
    'registrationMs': _registrationMs,
    'families': [latin, arabic],
    'scope': 'fixed benchmark corpus; not arbitrary Unicode coverage',
  };

  Future<void> ensureLoaded() {
    if (isReady) return SynchronousFuture<void>(null);
    return _pending ??= Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final clock = Stopwatch()..start();
    try {
      // Read every asset first so a missing file cannot partly register a family.
      final bytes = <String, ByteData>{};
      for (final paths in assets.values) {
        for (final path in paths) {
          bytes[path] = await _bundle
              .load(path)
              .timeout(
                const Duration(seconds: 30),
                onTimeout: () =>
                    throw TimeoutException('Loading font asset: $path'),
              );
          if (bytes[path]!.lengthInBytes < 12 ||
              bytes[path]!.getUint32(0) != 0x00010000) {
            throw FormatException('Invalid benchmark TrueType asset: $path');
          }
        }
      }
      for (final entry in assets.entries) {
        for (final path in entry.value) {
          if (_registered.contains(path)) continue;
          final loader = _loader(entry.key);
          loader.addFont(SynchronousFuture(bytes[path]!));
          await loader.load();
          _registered.add(path);
        }
      }
      _registrationMs = clock.elapsedMicroseconds / 1000;
    } catch (error) {
      _pending = null;
      debugPrint('PHASE0_FONT_FAILED ${jsonEncode({'error': '$error'})}');
      rethrow;
    }
  }
}
