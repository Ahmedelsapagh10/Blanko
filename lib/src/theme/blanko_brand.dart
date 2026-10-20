import 'package:flutter/material.dart';

/// Blanko official brand tokens and styling (Brand Identity v1.0).
///
/// Use the supplied vector logos and exact color tokens. Keep user-drawn
/// ink and whiteboard document elements independent from these UI tokens.
abstract final class BlankoBrand {
  static const String appName = 'Blanko';
  static const String tagline = 'Where ideas take shape.';
  static const String appStoreSubtitle = 'Sketch. Think. Create.';
  static const String descriptor =
      'Your digital space to think, sketch, and create.';

  static const String onboardingHeading = 'Your ideas start here.';
  static const String onboardingBody =
      'A simple space to think, sketch, and bring ideas to life.';
  static const String emptyStateHeading =
      'A blank space. Endless possibilities.';
  static const String primaryCta = 'Create a board';
  static const String defaultBoardTitle = 'Untitled board';

  // Core brand palette
  static const Color ink = Color(0xFF15191F);
  static const Color originBlue = Color(0xFF4464F6);
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F8FA);
  static const Color border = Color(0xFFE7EAF0);
  static const Color mutedText = Color(0xFF687386);

  // Dark mode surface tokens
  static const Color darkSurface = Color(0xFF15191F);
  static const Color darkSurfaceContainer = Color(0xFF1E232B);
  static const Color darkBorder = Color(0xFF2C323D);
  static const Color darkMutedText = Color(0xFF98A2B3);
  static const Color onDark = Color(0xFFFFFFFF);
}

/// Production Blanko themes for light and dark modes.
abstract final class BlankoTheme {
  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = [
    'IBM Plex Sans Arabic',
    'Roboto',
    'Noto Sans Arabic',
  ];

  static ThemeData get light {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: BlankoBrand.originBlue,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEBF0FF),
      onPrimaryContainer: BlankoBrand.ink,
      secondary: BlankoBrand.originBlue,
      onSecondary: Colors.white,
      surface: BlankoBrand.surface,
      onSurface: BlankoBrand.ink,
      surfaceContainerLowest: BlankoBrand.canvas,
      surfaceContainerLow: BlankoBrand.surface,
      surfaceContainer: Color(0xFFEFF1F5),
      surfaceContainerHigh: Color(0xFFE7EAF0),
      outline: BlankoBrand.border,
      outlineVariant: BlankoBrand.border,
      error: Color(0xFFDC2626),
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF991B1B),
    );

    return _refine(
      ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: BlankoBrand.canvas,
        dividerColor: BlankoBrand.border,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        appBarTheme: const AppBarTheme(
          backgroundColor: BlankoBrand.surface,
          foregroundColor: BlankoBrand.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: BlankoBrand.originBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: BlankoBrand.originBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: BlankoBrand.border),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: BlankoBrand.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: BlankoBrand.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: BlankoBrand.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: BlankoBrand.originBlue,
              width: 1.5,
            ),
          ),
          labelStyle: const TextStyle(color: BlankoBrand.mutedText),
          hintStyle: const TextStyle(color: BlankoBrand.mutedText),
        ),
      ),
    );
  }

  static ThemeData get dark {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: BlankoBrand.originBlue,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF1E2B58),
      onPrimaryContainer: BlankoBrand.onDark,
      secondary: BlankoBrand.originBlue,
      onSecondary: Colors.white,
      surface: BlankoBrand.darkSurface,
      onSurface: BlankoBrand.onDark,
      surfaceContainerLowest: Color(0xFF0F1216),
      surfaceContainerLow: BlankoBrand.darkSurfaceContainer,
      surfaceContainer: Color(0xFF242A34),
      surfaceContainerHigh: Color(0xFF2C323D),
      outline: BlankoBrand.darkBorder,
      outlineVariant: BlankoBrand.darkBorder,
      error: Color(0xFFFF8D86),
      onError: Color(0xFF4C1111),
      errorContainer: Color(0xFF451A1A),
      onErrorContainer: Color(0xFFFCA5A5),
    );

    return _refine(
      ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: BlankoBrand.darkSurface,
        dividerColor: BlankoBrand.darkBorder,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        appBarTheme: const AppBarTheme(
          backgroundColor: BlankoBrand.darkSurface,
          foregroundColor: BlankoBrand.onDark,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: BlankoBrand.originBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: BlankoBrand.originBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: BlankoBrand.darkSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: BlankoBrand.darkBorder),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: BlankoBrand.darkSurfaceContainer,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: BlankoBrand.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: BlankoBrand.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: BlankoBrand.originBlue,
              width: 1.5,
            ),
          ),
          labelStyle: const TextStyle(color: BlankoBrand.darkMutedText),
          hintStyle: const TextStyle(color: BlankoBrand.darkMutedText),
        ),
      ),
    );
  }

  static ThemeData _refine(ThemeData theme) {
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final muted = dark ? BlankoBrand.darkMutedText : BlankoBrand.mutedText;
    final accentText = dark ? const Color(0xFFA6B5FF) : colors.primary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BlankoMetrics.controlRadius),
    );
    return theme.copyWith(
      colorScheme: colors.copyWith(onSurfaceVariant: muted),
      hoverColor: colors.primary.withValues(alpha: .06),
      focusColor: colors.primary.withValues(alpha: .14),
      textTheme: theme.textTheme.copyWith(
        headlineSmall: theme.textTheme.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
        ),
        titleLarge: theme.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -.3,
        ),
        titleMedium: theme.textTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.4,
          color: muted,
        ),
        labelLarge: theme.textTheme.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: WidgetStateProperty.resolveWith(
            (states) => shape.copyWith(
              side: states.contains(WidgetState.focused)
                  ? BorderSide(color: accentText, width: 2)
                  : BorderSide.none,
            ),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: theme.filledButtonTheme.style?.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentText,
          minimumSize: const Size(44, 44),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onSurface,
          minimumSize: const Size(44, 44),
          shape: shape,
          side: BorderSide(color: colors.outline),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BlankoMetrics.panelRadius),
          side: BorderSide(color: colors.outline),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BlankoMetrics.panelRadius),
          side: BorderSide(color: colors.outline),
        ),
        textStyle: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerLow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BlankoMetrics.panelRadius),
              side: BorderSide(color: colors.outline),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFFE7EAF0) : BlankoBrand.ink,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontSize: 12,
          color: dark ? BlankoBrand.ink : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFFE7EAF0) : BlankoBrand.ink,
        contentTextStyle: TextStyle(
          color: dark ? BlankoBrand.ink : Colors.white,
        ),
        actionTextColor: dark
            ? const Color(0xFF2948D1)
            : const Color(0xFFBAC5FF),
        shape: shape,
      ),
      dividerTheme: DividerThemeData(
        color: colors.outline,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accentText,
        selectionColor: colors.primary.withValues(alpha: .25),
        selectionHandleColor: accentText,
      ),
    );
  }
}

/// Shared spacing and shape values for the editor and library chrome.
abstract final class BlankoMetrics {
  static const double compact = 8;
  static const double spacing = 12;
  static const double padding = 16;
  static const double controlRadius = 8;
  static const double panelRadius = 12;
}

/// Official Blanko 'O' Symbol vector widget.
///
/// Draws the canonical SVG master geometry: an open circular stroke with an
/// Origin Blue dot marking the inception point of an idea.
class BlankoSymbol extends StatelessWidget {
  const BlankoSymbol({
    super.key,
    this.size = 28,
    this.color,
    this.dotColor = BlankoBrand.originBlue,
  });

  final double size;
  final Color? color;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ??
        (Theme.of(context).brightness == Brightness.dark
            ? BlankoBrand.onDark
            : BlankoBrand.ink);

    return Semantics(
      label: 'Blanko Logo',
      child: CustomPaint(
        size: Size(size, size),
        painter: _BlankoSymbolPainter(
          strokeColor: effectiveColor,
          dotColor: dotColor,
        ),
      ),
    );
  }
}

class _BlankoSymbolPainter extends CustomPainter {
  const _BlankoSymbolPainter({
    required this.strokeColor,
    required this.dotColor,
  });

  final Color strokeColor;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1024.0, size.height / 1024.0);

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 92
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(642.166, 232.857)
      ..arcToPoint(
        const Offset(783.948, 367.403),
        radius: const Radius.circular(308),
        largeArc: true,
        clockwise: false,
      );

    canvas.drawPath(path, strokePaint);

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(722.055, 286.743), 26.680, dotPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BlankoSymbolPainter oldDelegate) =>
      strokeColor != oldDelegate.strokeColor ||
      dotColor != oldDelegate.dotColor;
}

/// Official Blanko Wordmark vector widget.
///
/// Renders the exact outlines of the canonical wordmark artwork (never retyped).
class BlankoWordmark extends StatelessWidget {
  const BlankoWordmark({
    super.key,
    this.height = 24,
    this.color,
    this.dotColor = BlankoBrand.originBlue,
  });

  final double height;
  final Color? color;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ??
        (Theme.of(context).brightness == Brightness.dark
            ? BlankoBrand.onDark
            : BlankoBrand.ink);

    // viewBox 0 0 2048 1080 -> aspect ratio 2048 / 1080 = 1.8963
    final width = height * (2048.0 / 1080.0);

    return Semantics(
      label: 'Blanko',
      child: CustomPaint(
        size: Size(width, height),
        painter: _BlankoWordmarkPainter(
          fillColor: effectiveColor,
          dotColor: dotColor,
        ),
      ),
    );
  }
}

class _BlankoWordmarkPainter extends CustomPainter {
  _BlankoWordmarkPainter({required this.fillColor, required this.dotColor});

  final Color fillColor;
  final Color dotColor;

  static Path? _cachedLettersPath;
  static Path? _cachedArcPath;

  static void _ensurePaths() {
    if (_cachedLettersPath != null) return;

    final combined = Path();

    void addLetter(String svgPath, double tx, double ty) {
      final p = _parseSvgPath(svgPath);
      final matrix = Matrix4.identity();
      matrix.storage[0] = 0.23500;
      matrix.storage[5] = -0.23500;
      matrix.storage[12] = tx;
      matrix.storage[13] = ty;
      combined.addPath(p.transform(matrix.storage), Offset.zero);
    }

    // Letter 'B'
    addLetter(
      'M124 0H726C1071 0 1252 168 1252 419C1252 631 1114 754 936 775V777C1096 821 1195 931 1195 1103C1195 1336 1014 1490 700 1490H124ZM384 215V652H704C880 652 981 566 981 428C981 291 878 215 698 215ZM384 859V1275H688C839 1275 931 1195 931 1067C931 940 839 859 688 859Z',
      243.9586,
      715.0750,
    );

    // Letter 'l'
    addLetter('M364 1490H112V0H364Z', 553.2186, 715.0750);

    // Letter 'a'
    addLetter(
      'M434 -17C606 -17 695 55 745 149H749V0H997V720C997 940 834 1077 559 1077C283 1077 111 938 99 728H342C349 817 431 881 554 881C675 881 747 817 747 727V719C747 647 680 644 484 622C266 599 69 540 69 300C69 89 224 -17 434 -17ZM496 170C386 170 315 219 315 302C315 398 407 437 515 453C619 469 717 485 748 505V391C748 268 661 170 496 170Z',
      665.0786,
      715.0750,
    );

    // Letter 'n'
    addLetter(
      'M364 597C364 777 463 856 595 856C730 856 808 775 808 620V0H1061V660C1061 931 905 1077 684 1077C539 1077 432 1013 360 894V1056H112V0H364Z',
      925.4586,
      715.0750,
    );

    // Letter 'k'
    addLetter(
      'M112 0H364V353L460 452L806 0H1107L652 600L1081 1056H778L367 628H364V1490H112Z',
      1201.1136,
      715.0750,
    );

    _cachedLettersPath = combined;

    // O arc
    final oPath = Path()
      ..moveTo(1711.043, 394.022)
      ..arcToPoint(
        const Offset(1785.188, 464.383),
        radius: const Radius.circular(161.069),
        largeArc: true,
        clockwise: false,
      );
    _cachedArcPath = oPath;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensurePaths();

    canvas.save();
    canvas.scale(size.width / 2048.0, size.height / 1080.0);

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(_cachedLettersPath!, fillPaint);

    final strokePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 50.772
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(_cachedArcPath!, strokePaint);

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(1752.821, 422.202), 14.724, dotPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BlankoWordmarkPainter oldDelegate) =>
      fillColor != oldDelegate.fillColor || dotColor != oldDelegate.dotColor;
}

Path _parseSvgPath(String d) {
  final path = Path();
  final tokens = <String>[];
  final matches = RegExp(
    r'([a-zA-Z])|([-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?)',
  ).allMatches(d);
  for (final m in matches) {
    tokens.add(m.group(0)!);
  }

  var i = 0;
  var currentX = 0.0;
  var currentY = 0.0;

  while (i < tokens.length) {
    final cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        currentX = double.parse(tokens[i++]);
        currentY = double.parse(tokens[i++]);
        path.moveTo(currentX, currentY);
        break;
      case 'L':
        currentX = double.parse(tokens[i++]);
        currentY = double.parse(tokens[i++]);
        path.lineTo(currentX, currentY);
        break;
      case 'H':
        currentX = double.parse(tokens[i++]);
        path.lineTo(currentX, currentY);
        break;
      case 'V':
        currentY = double.parse(tokens[i++]);
        path.lineTo(currentX, currentY);
        break;
      case 'C':
        while (i < tokens.length &&
            !RegExp(r'^[a-zA-Z]$').hasMatch(tokens[i])) {
          final x1 = double.parse(tokens[i++]);
          final y1 = double.parse(tokens[i++]);
          final x2 = double.parse(tokens[i++]);
          final y2 = double.parse(tokens[i++]);
          currentX = double.parse(tokens[i++]);
          currentY = double.parse(tokens[i++]);
          path.cubicTo(x1, y1, x2, y2, currentX, currentY);
        }
        break;
      case 'Z':
      case 'z':
        path.close();
        break;
    }
  }

  return path;
}
