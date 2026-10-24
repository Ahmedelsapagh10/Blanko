import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/editor_text.dart';
import 'package:whiteboard/src/editor/png_export.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

RichTextData rich(List<Map<String, Object?>> operations) =>
    RichTextData.fromJson({'version': 1, 'delta': operations});

final style = ElementTextStyle(
  fontId: 'default',
  fontSize: 20,
  color: 0xff000000,
);
TextElementContent content(RichTextData value, {double width = 240}) =>
    TextElementContent(
      text: value.plainText,
      richText: value,
      bounds: Bounds2(0, 0, width, 200),
      style: style,
    );

Future<Uint8List> imagePixels(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

Future<Uint8List> layoutPixels(ElementTextLayout layout) async {
  final recorder = ui.PictureRecorder();
  layout.paint(Canvas(recorder), Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 200);
  try {
    return await imagePixels(image);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

({int left, int right, int top, int bottom, int count}) pixelExtent(
  Uint8List pixels,
  bool Function(int r, int g, int b, int a) matches,
) {
  var left = 240;
  var right = -1;
  var top = 200;
  var bottom = -1;
  var count = 0;
  for (var y = 0; y < 200; y++) {
    for (var x = 0; x < 240; x++) {
      final i = (y * 240 + x) * 4;
      if (matches(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])) {
        left = x < left ? x : left;
        right = x > right ? x : right;
        top = y < top ? y : top;
        bottom = y > bottom ? y : bottom;
        count++;
      }
    }
  }
  return (left: left, right: right, top: top, bottom: bottom, count: count);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureEditorFonts);

  test(
    'legacy metrics and appearance retain the original text painter',
    () async {
      final legacy = TextElementContent(
        text: 'Hello مرحبا\nworld',
        bounds: Bounds2(0, 0, 180, 200),
        style: style,
      );
      final layout = layoutElementText(legacy);
      final original = TextPainter(
        text: TextSpan(
          text: legacy.text,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const [
              'IBM Plex Sans Arabic',
              'Roboto',
              'Noto Sans Arabic',
            ],
            fontSize: 20,
            color: Colors.black,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.start,
      )..layout(maxWidth: 180);
      try {
        expect(layout.height, original.height);
        expect(layout.width, original.width);
        expect((await layoutPixels(layout)).any((value) => value != 0), isTrue);
      } finally {
        original.dispose();
        layout.dispose();
      }
    },
  );

  test(
    'mixed attributes and Arabic paragraphs paint with independent alignment',
    () async {
      final value = rich([
        {
          'insert': 'Bold ',
          'attributes': {'bold': true, 'color': '#FF0000'},
        },
        {
          'insert': 'Blue',
          'attributes': {
            'italic': true,
            'underline': true,
            'strike': true,
            'size': '28',
            'color': '#0000FF',
            'background': '#00FF00',
          },
        },
        {
          'insert': '\n',
          'attributes': {'align': 'left'},
        },
        {
          'insert': 'مرحبا',
          'attributes': {'font': 'Noto Sans Arabic', 'color': '#FF00FF'},
        },
        {
          'insert': '\n',
          'attributes': {'align': 'right', 'direction': 'rtl'},
        },
        {
          'insert': 'Link',
          'attributes': {'link': 'https://example.com'},
        },
        {
          'insert': '\n',
          'attributes': {'align': 'center'},
        },
      ]);
      final layout = layoutElementText(content(value));
      try {
        final pixels = await layoutPixels(layout);
        final red = pixelExtent(
          pixels,
          (r, g, b, a) => r > 180 && g < 60 && b < 60 && a > 100,
        );
        final blue = pixelExtent(
          pixels,
          (r, g, b, a) => b > 180 && r < 60 && g < 60 && a > 100,
        );
        final highlight = pixelExtent(
          pixels,
          (r, g, b, a) => g > 180 && r < 60 && b < 60 && a > 100,
        );
        final arabic = pixelExtent(
          pixels,
          (r, g, b, a) => r > 180 && b > 180 && g < 60 && a > 100,
        );
        final link = pixelExtent(
          pixels,
          (r, g, b, a) => b > 180 && g > 90 && r < 80 && a > 100,
        );
        expect(red.count, greaterThan(30));
        expect(blue.count, greaterThan(30));
        expect(highlight.count, greaterThan(100));
        expect(arabic.count, greaterThan(30));
        expect(link.count, greaterThan(20));
        expect(blue.left, greaterThan(red.left));
        expect(arabic.left, greaterThan(120));
        expect(arabic.top, greaterThan(red.bottom));
        expect(link.left, inInclusiveRange(70, 120));
        expect(link.top, greaterThan(arabic.bottom));
      } finally {
        layout.dispose();
      }
    },
  );

  test('narrow rich paragraphs wrap and empty lines retain line height', () {
    final value = rich([
      {'insert': 'A long paragraph of text that should wrap\n\n'},
    ]);
    final narrow = layoutElementText(content(value, width: 70));
    final wide = layoutElementText(content(value));
    final empty = layoutElementText(
      content(
        rich([
          {'insert': '\n'},
        ]),
      ),
    );
    try {
      expect(narrow.height, greaterThan(wide.height));
      expect(empty.height, greaterThan(20));
      expect(empty.height, lessThan(40));
    } finally {
      narrow.dispose();
      wide.dispose();
      empty.dispose();
    }
  });

  test(
    'lists reserve directional leading space and number consecutive lines',
    () async {
      final value = rich([
        {'insert': 'First'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'Second'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'مرحبا'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet', 'direction': 'rtl'},
        },
      ]);
      final layout = layoutElementText(content(value));
      try {
        final pixels = await layoutPixels(layout);
        var leftMarker = 0;
        var rightMarker = 0;
        for (var y = 0; y < 200; y++) {
          for (var x = 0; x < 240; x++) {
            if (pixels[(y * 240 + x) * 4 + 3] > 100) {
              if (x < 30 && y < 50) leftMarker++;
              if (x > 210 && y > 50) rightMarker++;
            }
          }
        }
        expect(leftMarker, greaterThan(15));
        expect(rightMarker, greaterThan(5));
      } finally {
        layout.dispose();
      }
    },
  );

  test(
    'PNG export exactly shares rich layout at one world pixel per pixel',
    () async {
      final value = rich([
        {
          'insert': 'System ',
          'attributes': {'bold': true, 'color': '#FF0000'},
        },
        {
          'insert': 'مرحبا',
          'attributes': {'color': '#0000FF'},
        },
        {
          'insert': '\n',
          'attributes': {'align': 'center'},
        },
        {
          'insert': 'Highlighted',
          'attributes': {'background': '#FFFF00', 'underline': true},
        },
        {'insert': '\n'},
      ]);
      final text = content(value);
      final layout = layoutElementText(text);
      final png = await renderBoardPng(
        document: BoardDocument(
          id: 'rich',
          revision: 0,
          elements: [DocumentElement(id: ElementId('text'), content: text)],
        ),
        store: null,
        bounds: Bounds2(0, 0, 240, 200),
        width: 240,
        height: 200,
      );
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      try {
        expect(await imagePixels(image), await layoutPixels(layout));
      } finally {
        image.dispose();
        codec.dispose();
        layout.dispose();
      }
    },
  );

  testWidgets('committed mixed paragraph metrics match the real Quill widget', (
    tester,
  ) async {
    final value = rich([
      {
        'insert': 'Bold ',
        'attributes': {'bold': true},
      },
      {
        'insert': 'Blue',
        'attributes': {
          'color': '#0000FF',
          'size': '28',
          'italic': true,
          'underline': true,
          'strike': true,
          'background': '#FFFF00',
        },
      },
      {'insert': '\n'},
      {
        'insert': 'مرحبا',
        'attributes': {'font': 'Noto Sans Arabic'},
      },
      {
        'insert': '\n',
        'attributes': {'direction': 'rtl', 'align': 'center'},
      },
      {
        'insert': 'Item',
        'attributes': {
          'bold': true,
          'italic': true,
          'color': '#FF0000',
          'underline': true,
        },
      },
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {
        'insert': 'Link',
        'attributes': {'link': 'https://example.com'},
      },
      {'insert': '\n'},
    ]);
    final controller = q.QuillController(
      document: q.Document.fromJson(value.delta),
      selection: const TextSelection.collapsed(offset: 0),
    )..readOnly = true;
    final focus = FocusNode();
    final scroll = ScrollController();
    final boundaryKey = GlobalKey();
    final paragraphStyle = baseElementTextStyle(style);
    final block = q.DefaultTextBlockStyle(
      paragraphStyle,
      const q.HorizontalSpacing(0, 0),
      q.VerticalSpacing.zero,
      q.VerticalSpacing.zero,
      null,
    );
    final layout = layoutElementText(content(value));
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [q.FlutterQuillLocalizations.delegate],
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.black,
                  decoration: TextDecoration.none,
                ),
                child: SizedBox(
                  width: 240,
                  height: 200,
                  child: q.QuillEditor(
                    controller: controller,
                    focusNode: focus,
                    scrollController: scroll,
                    config: q.QuillEditorConfig(
                      scrollable: false,
                      padding: EdgeInsets.zero,
                      showCursor: false,
                      customStyles: q.DefaultStyles(
                        paragraph: block,
                        leading: block,
                        align: block,
                        link: const TextStyle(
                          color: Color(0xff2196f3),
                          decoration: TextDecoration.underline,
                        ),
                        lists: q.DefaultListBlockStyle(
                          paragraphStyle,
                          const q.HorizontalSpacing(0, 0),
                          q.VerticalSpacing.zero,
                          q.VerticalSpacing.zero,
                          null,
                          null,
                          indentWidthBuilder: (block, _, _, _) =>
                              q.HorizontalSpacing(
                                block.style.containsKey(q.Attribute.list.key)
                                    ? 32
                                    : 0,
                                0,
                              ),
                          numberPointWidthBuilder: (_, _) => 32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final actual = await imagePixels(image);
          final expected = await layoutPixels(layout);
          final actualExtent = pixelExtent(actual, (r, g, b, a) => a > 100);
          final expectedExtent = pixelExtent(expected, (r, g, b, a) => a > 100);
          expect(actual, expected);
          expect(actualExtent.bottom, closeTo(expectedExtent.bottom, 1));
          expect(actualExtent.top, closeTo(expectedExtent.top, 1));
          final actualBlue = pixelExtent(
            actual,
            (r, g, b, a) => b > 180 && r < 60 && g < 60 && a > 100,
          );
          final expectedBlue = pixelExtent(
            expected,
            (r, g, b, a) => b > 180 && r < 60 && g < 60 && a > 100,
          );
          expect(actualBlue.left, closeTo(expectedBlue.left, 1));
          expect(actualBlue.right, closeTo(expectedBlue.right, 1));
          expect(actualBlue.bottom, closeTo(expectedBlue.bottom, 1));
        } finally {
          image.dispose();
        }
      });
      await tester.pumpWidget(const SizedBox());
    } finally {
      layout.dispose();
      controller.dispose();
      focus.dispose();
      scroll.dispose();
    }
  });
}
