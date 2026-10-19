import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/benchmark_main.dart';
import 'package:whiteboard/src/benchmarks/benchmark_fonts.dart';
import 'package:whiteboard/src/benchmarks/benchmark_page.dart';

class _Bundle extends CachingAssetBundle {
  Object? failure;
  Completer<void>? gate;
  int reads = 0;

  @override
  Future<ByteData> load(String key) async {
    reads++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return ByteData(12)..setUint32(0, 0x00010000);
  }
}

class _Loader extends FontLoader {
  _Loader(super.family, this.register);
  final Future<void> Function() register;
  @override
  Future<void> loadFont(Uint8List list, String family) => register();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent callers wait for all faces; later loads reuse registration',
    () async {
      final bundle = _Bundle()..gate = Completer<void>();
      var registrations = 0;
      final fonts = BenchmarkFonts(
        bundle: bundle,
        loader: (family) => _Loader(family, () async => registrations++),
      );
      final first = fonts.ensureLoaded();
      expect(identical(first, fonts.ensureLoaded()), isTrue);
      expect(fonts.isReady, isFalse);
      bundle.gate!.complete();
      await first;
      expect(fonts.isReady, isTrue);
      expect(registrations, 4);
      expect(bundle.reads, 4);
      await fonts.ensureLoaded();
      expect(registrations, 4);
      expect(bundle.reads, 4);
      expect(fonts.report['registrationMs'], isA<double>());
    },
  );

  test('missing assets fail before registration and can be retried', () async {
    final bundle = _Bundle()..failure = StateError('missing asset');
    var registrations = 0;
    final fonts = BenchmarkFonts(
      bundle: bundle,
      loader: (family) => _Loader(family, () async => registrations++),
    );
    await expectLater(fonts.ensureLoaded(), throwsStateError);
    expect(fonts.isReady, isFalse);
    expect(registrations, 0);
    bundle.failure = null;
    await fonts.ensureLoaded();
    expect(fonts.isReady, isTrue);
    expect(registrations, 4);
  });

  test('engine failure retries only unfinished faces', () async {
    var calls = 0;
    final fonts = BenchmarkFonts(
      bundle: _Bundle(),
      loader: (family) => _Loader(family, () async {
        calls++;
        if (calls == 2) throw StateError('engine rejected registration');
      }),
    );
    await expectLater(fonts.ensureLoaded(), throwsStateError);
    expect(fonts.isReady, isFalse);
    await fonts.ensureLoaded();
    expect(calls, 5);
    expect(fonts.isReady, isTrue);
  });

  testWidgets(
    'timed out asset cannot publish readiness when it later arrives',
    (tester) async {
      final bundle = _Bundle()..gate = Completer<void>();
      var registrations = 0;
      final fonts = BenchmarkFonts(
        bundle: bundle,
        loader: (family) => _Loader(family, () async => registrations++),
      );
      final failed = expectLater(
        fonts.ensureLoaded(),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      await failed;
      bundle.gate!.complete();
      await tester.pump();
      expect(fonts.isReady, isFalse);
      expect(registrations, 0);
      final retry = fonts.ensureLoaded();
      await tester.pump();
      await retry;
      expect(fonts.isReady, isTrue);
      expect(registrations, 4);
    },
  );

  testWidgets(
    'font loading blocks scene creation; disposal suppresses publication',
    (tester) async {
      final bundle = _Bundle()..gate = Completer<void>();
      final fonts = BenchmarkFonts(
        bundle: bundle,
        loader: (family) => _Loader(family, () async {}),
      );
      await tester.pumpWidget(BenchmarkApp(fonts: fonts));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(BenchmarkPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      bundle.gate!.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BenchmarkPage), findsNothing);
    },
  );

  testWidgets('font failure is actionable and cannot start a benchmark', (
    tester,
  ) async {
    final fonts = BenchmarkFonts(
      bundle: _Bundle()..failure = StateError('missing font'),
    );
    await tester.pumpWidget(BenchmarkApp(fonts: fonts));
    await tester.pump();
    expect(
      find.textContaining('Could not load benchmark fonts:'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(BenchmarkPage), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(BenchmarkPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'real Latin, Arabic and mixed paragraphs remain stable after readiness',
    (tester) async {
      await tester.runAsync(() async {
        await BenchmarkFonts.instance.ensureLoaded();
        final sizes = <Size>[];
        for (var repeat = 0; repeat < 2; repeat++) {
          for (final text in [
            'Explore ideas 0123456789',
            'فكرة جديدة',
            'فكرة جديدة Whiteboard 123',
          ]) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: const TextStyle(
                  fontFamily: BenchmarkFonts.latin,
                  fontFamilyFallback: [BenchmarkFonts.arabic],
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
              textDirection: TextDirection.rtl,
            )..layout(maxWidth: 240);
            try {
              expect(painter.width, greaterThan(20));
              expect(painter.height, greaterThan(10));
              expect(painter.computeLineMetrics(), isNotEmpty);
              if (repeat == 0) {
                sizes.add(painter.size);
              } else {
                expect(painter.size, sizes.removeAt(0));
              }
            } finally {
              painter.dispose();
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
    },
  );
}
