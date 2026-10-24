import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../document/element.dart';

bool _fontsLoaded = false;
Future<void>? _fontLoad;

/// Register bundled families before creating persistent text layouts.
Future<void> ensureEditorFonts() {
  if (_fontsLoaded) return SynchronousFuture<void>(null);
  return _fontLoad ??= _loadFonts();
}

Future<void> _loadFonts() async {
  try {
    for (final entry in const {
      'Roboto': [
        'assets/benchmark_fonts/Roboto-Regular.ttf',
        'assets/benchmark_fonts/Roboto-Bold.ttf',
      ],
      'Noto Sans Arabic': ['assets/benchmark_fonts/NotoSansArabic-Regular.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load().timeout(const Duration(seconds: 15));
    }
    _fontsLoaded = true;
  } catch (_) {
    _fontLoad = null;
    rethrow;
  }
}

TextDirection elementTextDirection(
  String text,
  ElementTextDirection direction,
) {
  if (direction == ElementTextDirection.rtl) return TextDirection.rtl;
  if (direction == ElementTextDirection.ltr) return TextDirection.ltr;
  for (final rune in text.runes) {
    if (rune >= 0x590 && rune <= 0x8ff ||
        rune >= 0xfb1d && rune <= 0xfdff ||
        rune >= 0xfe70 && rune <= 0xfefc) {
      return TextDirection.rtl;
    }
    if (rune >= 65 && rune <= 90 || rune >= 97 && rune <= 122) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}

/// The same paragraph metrics are used by the inline editor and saved artwork.
TextStyle baseElementTextStyle(ElementTextStyle style) => TextStyle(
  fontFamily: 'Roboto',
  fontFamilyFallback: const ['Noto Sans Arabic'],
  fontSize: style.fontSize,
  color: Color(style.color),
  height: 1.3,
);

/// Owns only Flutter layout resources; no resources enter document state.
final class ElementTextLayout {
  ElementTextLayout._(this._paragraphs, this.width, this.height);

  final List<({TextPainter painter, Offset offset})> _paragraphs;
  final double width;
  final double height;

  void paint(Canvas canvas, Offset offset) {
    for (final paragraph in _paragraphs) {
      paragraph.painter.paint(canvas, offset + paragraph.offset);
    }
  }

  void dispose() {
    for (final paragraph in _paragraphs) {
      paragraph.painter.dispose();
    }
  }
}

/// Caller owns and disposes the returned layout.
ElementTextLayout layoutElementText(ElementContent content) {
  final (text, bounds, style, direction, alignment) = switch (content) {
    TextElementContent() => (
      content.text,
      content.bounds,
      content.style,
      content.direction,
      content.alignment,
    ),
    StickyNoteElementContent() => (
      content.text,
      content.bounds,
      content.style,
      content.direction,
      content.alignment,
    ),
    _ => throw ArgumentError('Expected text or sticky note.'),
  };
  final padding = content is StickyNoteElementContent ? 12.0 : 0.0;
  final richText = switch (content) {
    TextElementContent() => content.richText,
    StickyNoteElementContent() => content.richText,
    _ => null,
  };
  final width = (bounds.width - padding * 2).clamp(1.0, double.infinity);
  if (richText != null) {
    return _layoutRichText(richText, width, style, direction, alignment);
  }
  // Preserve pre-rich-text typography for untouched legacy elements.
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const [
          'IBM Plex Sans Arabic',
          'Roboto',
          'Noto Sans Arabic',
        ],
        fontSize: style.fontSize,
        color: Color(style.color),
        height: 1.3,
      ),
    ),
    textDirection: elementTextDirection(text, direction),
    textAlign: switch (alignment) {
      ElementTextAlignment.start => TextAlign.start,
      ElementTextAlignment.end => TextAlign.end,
      ElementTextAlignment.center => TextAlign.center,
      ElementTextAlignment.left => TextAlign.left,
      ElementTextAlignment.right => TextAlign.right,
    },
  )..layout(maxWidth: width);
  return ElementTextLayout._(
    [(painter: painter, offset: Offset.zero)],
    painter.width,
    painter.height,
  );
}

Color _richColor(String value) => Color(
  int.parse(
    value.length == 7 ? 'FF${value.substring(1)}' : value.substring(1),
    radix: 16,
  ),
);

TextStyle _spanStyle(TextStyle base, Map<String, Object?> attributes) {
  final decorations = <TextDecoration>[
    if (attributes['underline'] == true || attributes.containsKey('link'))
      TextDecoration.underline,
    if (attributes['strike'] == true) TextDecoration.lineThrough,
  ];
  return base.copyWith(
    fontWeight: attributes['bold'] == true ? FontWeight.bold : null,
    fontStyle: attributes['italic'] == true ? FontStyle.italic : null,
    decoration: decorations.isEmpty
        ? null
        : TextDecoration.combine(decorations),
    fontSize: double.tryParse('${attributes['size']}'),
    fontFamily: attributes['font'] as String?,
    color: attributes['color'] is String
        ? _richColor(attributes['color']! as String)
        : attributes.containsKey('link')
        ? const Color(0xff2196f3)
        : null,
    backgroundColor: attributes['background'] is String
        ? _richColor(attributes['background']! as String)
        : null,
  );
}

ElementTextLayout _layoutRichText(
  RichTextData richText,
  double width,
  ElementTextStyle style,
  ElementTextDirection direction,
  ElementTextAlignment alignment,
) {
  final paragraphs = <({TextPainter painter, Offset offset})>[];
  final spans = <TextSpan>[];
  Map<String, Object?> firstAttributes = const {};
  final text = StringBuffer();
  final base = baseElementTextStyle(style);
  var top = 0.0;
  var orderedIndex = 0;

  void finishParagraph(Map<String, Object?> attributes) {
    final paragraphDirection = switch (attributes['direction']) {
      'rtl' => TextDirection.rtl,
      'ltr' => TextDirection.ltr,
      _ => elementTextDirection(text.toString(), direction),
    };
    final textAlign = switch (attributes['align']) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      _ => switch (alignment) {
        ElementTextAlignment.start => TextAlign.start,
        ElementTextAlignment.end => TextAlign.end,
        ElementTextAlignment.center => TextAlign.center,
        ElementTextAlignment.left => TextAlign.left,
        ElementTextAlignment.right => TextAlign.right,
      },
    };
    final list = attributes['list'];
    final indent = list == null ? 0.0 : 32.0;
    final painter =
        TextPainter(
          text: TextSpan(
            style: base,
            children: spans.isEmpty
                ? [const TextSpan(text: '\u200B')]
                : List.of(spans),
          ),
          textDirection: paragraphDirection,
          textAlign: textAlign,
          strutStyle: StrutStyle.fromTextStyle(base),
        )..layout(
          minWidth: (width - indent).clamp(1.0, double.infinity),
          maxWidth: (width - indent).clamp(1.0, double.infinity),
        );
    paragraphs.add((
      painter: painter,
      offset: Offset(paragraphDirection == TextDirection.ltr ? indent : 0, top),
    ));
    if (list != null) {
      orderedIndex = list == 'ordered' ? orderedIndex + 1 : 0;
      final marker = TextPainter(
        text: TextSpan(
          text: list == 'ordered' ? '$orderedIndex.' : '•',
          style: base.copyWith(
            fontSize: double.tryParse('${firstAttributes['size']}'),
            color: firstAttributes['color'] is String
                ? _richColor(firstAttributes['color']! as String)
                : null,
            fontWeight: list == 'bullet' ? FontWeight.bold : null,
          ),
        ),
        textDirection: paragraphDirection,
      )..layout();
      // Match Quill leading padding at the directional end of its indent.
      paragraphs.add((
        painter: marker,
        offset: Offset(
          paragraphDirection == TextDirection.ltr
              ? indent - marker.width - style.fontSize / 2
              : width - indent + style.fontSize / 2,
          top,
        ),
      ));
    } else {
      orderedIndex = 0;
    }
    top += painter.height;
    spans.clear();
    firstAttributes = const {};
    text.clear();
  }

  try {
    for (final operation in richText.delta) {
      final attributes = operation['attributes'] is Map
          ? Map<String, Object?>.from(operation['attributes']! as Map)
          : const <String, Object?>{};
      final parts = (operation['insert']! as String).split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          if (spans.isEmpty) firstAttributes = attributes;
          spans.add(
            TextSpan(text: parts[i], style: _spanStyle(base, attributes)),
          );
          text.write(parts[i]);
        }
        if (i < parts.length - 1) finishParagraph(attributes);
      }
    }
    return ElementTextLayout._(paragraphs, width, top);
  } catch (_) {
    for (final paragraph in paragraphs) {
      paragraph.painter.dispose();
    }
    rethrow;
  }
}
