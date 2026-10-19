import 'package:flutter/material.dart';
import '../document/element.dart';

TextDirection elementTextDirection(
  String text,
  ElementTextDirection direction,
) {
  if (direction == ElementTextDirection.rtl) return TextDirection.rtl;
  if (direction == ElementTextDirection.ltr) return TextDirection.ltr;
  for (final rune in text.runes) {
    if (rune >= 0x590 && rune <= 0x8ff ||
        rune >= 0xfb1d && rune <= 0xfdff ||
        rune >= 0xfe70 && rune <= 0xfefc)
      return TextDirection.rtl;
    if (rune >= 65 && rune <= 90 || rune >= 97 && rune <= 122)
      return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

/// Caller owns and disposes the returned layout; no resources enter documents.
TextPainter layoutElementText(ElementContent content) {
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
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Noto Sans Arabic'],
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
  )..layout(maxWidth: (bounds.width - padding * 2).clamp(1, double.infinity));
}
