// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whiteboard/main.dart';
import 'package:whiteboard/benchmark_main.dart';
import 'package:whiteboard/src/benchmarks/benchmark_page.dart';
import 'package:whiteboard/src/editor/editor_canvas.dart';
import 'package:whiteboard/src/editor/editor_page.dart';

void main() {
  testWidgets(
    'BenchmarkApp opens the rendering lab and disposes during loading',
    (tester) async {
      await tester.pumpWidget(const BenchmarkApp());
      expect(find.byType(BenchmarkPage), findsOneWidget);
      expect(find.text('Whiteboard · Rendering spike'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Normal entry opens the usable editor', (tester) async {
    await tester.pumpWidget(const WhiteboardApp());
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.byType(EditorCanvas), findsOneWidget);
    expect(find.byTooltip('Pen (P)'), findsOneWidget);
    expect(find.byType(BenchmarkPage), findsNothing);
    expect(find.text('Session only · not saved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
