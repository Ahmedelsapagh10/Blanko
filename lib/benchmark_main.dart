import 'package:flutter/material.dart';

import 'src/benchmarks/benchmark_page.dart';
import 'src/benchmarks/benchmark_fonts.dart';

void main() {
  final startupClock = Stopwatch()..start();
  runApp(BenchmarkApp(startupClock: startupClock));
}

class BenchmarkApp extends StatefulWidget {
  const BenchmarkApp({super.key, this.startupClock, this.fonts});
  final Stopwatch? startupClock;
  final BenchmarkFonts? fonts;

  @override
  State<BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<BenchmarkApp> {
  Future<void>? _fonts;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Whiteboard rendering spike',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
      useMaterial3: true,
      fontFamily: BenchmarkFonts.latin,
      fontFamilyFallback: const [BenchmarkFonts.arabic],
    ),
    home: FutureBuilder<void>(
      future: _fonts ??= (widget.fonts ?? BenchmarkFonts.instance)
          .ensureLoaded(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load benchmark fonts: ${snapshot.error}'),
                  TextButton(
                    onPressed: () => setState(() {
                      _fonts = null;
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return BenchmarkPage(startupClock: widget.startupClock);
      },
    ),
  );
}
