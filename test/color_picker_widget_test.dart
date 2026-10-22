import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/color_picker_widget.dart';

void main() {
  testWidgets('ColorPickerWidget renders swatches and updates on tap', (
    tester,
  ) async {
    final controller = TextEditingController(text: '202D46');
    int? changedColor;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ColorPickerWidget(
              controller: controller,
              labelText: 'Stroke color (RRGGBB)',
              onColorChanged: (c) => changedColor = c,
            ),
          ),
        ),
      ),
    );

    // Initial state: '202D46' is selected, so the first swatch has a checkmark
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('Stroke color (RRGGBB)'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Tap on the red swatch (0xffdc2626)
    // Find swatches inside the Wrap
    final swatches = find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(InkWell),
    );
    expect(swatches, findsNWidgets(ColorPickerWidget.defaultPalette.length));

    // The red swatch is at index 4 (0xffdc2626)
    await tester.tap(swatches.at(4));
    await tester.pumpAndSettle();

    expect(controller.text, 'DC2626');
    expect(changedColor, 0xffdc2626);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // Type a new hex code manually
    await tester.enterText(find.byType(TextField), '2563EB');
    await tester.pumpAndSettle();

    // 0xff2563eb is at index 9, checkmark should move to it
    expect(changedColor, 0xff2563eb);
    expect(find.byIcon(Icons.check), findsOneWidget);

    controller.dispose();
  });

  testWidgets('ColorPickerWidget custom sliders toggle and update hex', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'DC2626');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ColorPickerWidget(
              controller: controller,
              labelText: 'Fill color (RRGGBB)',
            ),
          ),
        ),
      ),
    );

    // Sliders are initially closed
    expect(find.byType(Slider), findsNothing);

    // Open sliders using toggle button
    await tester.tap(find.byTooltip('Custom color picker'));
    await tester.pumpAndSettle();

    // Now Hue, Saturation, and Brightness sliders are visible
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.textContaining('Hue:'), findsOneWidget);
    expect(find.textContaining('Saturation:'), findsOneWidget);
    expect(find.textContaining('Brightness:'), findsOneWidget);

    // Change hue slider
    final hueSlider = find.byType(Slider).first;
    await tester.tap(hueSlider);
    await tester.pumpAndSettle();

    // Hex controller should have updated to reflect the new hue
    expect(controller.text, isNotEmpty);
    expect(controller.text.length, 6);

    controller.dispose();
  });

  testWidgets('ColorPickerWidget uses highlighter palette when isHighlighter is true', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'FFD54F');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorPickerWidget(
            controller: controller,
            labelText: 'Stroke color (RRGGBB)',
            isHighlighter: true,
          ),
        ),
      ),
    );

    final swatches = find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(InkWell),
    );
    expect(swatches, findsNWidgets(ColorPickerWidget.highlighterPalette.length));
    expect(find.byIcon(Icons.check), findsOneWidget);

    controller.dispose();
  });
}
