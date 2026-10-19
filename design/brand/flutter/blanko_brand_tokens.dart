import 'package:flutter/material.dart';

/// Blanko brand palette. Keep user-drawn ink colors independent from these UI tokens.
abstract final class BlankoBrand {
  static const String appName = 'Blanko';
  static const String tagline = 'Where ideas take shape.';

  static const Color ink = Color(0xFF15191F);
  static const Color originBlue = Color(0xFF4464F6);
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F8FA);
  static const Color border = Color(0xFFE7EAF0);
  static const Color mutedText = Color(0xFF687386);

  static const Color darkSurface = Color(0xFF15191F);
  static const Color onDark = Color(0xFFFFFFFF);
}
