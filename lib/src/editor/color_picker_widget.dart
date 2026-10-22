import 'package:flutter/material.dart';

/// Interactive color picker component with palette presets, visual sliders,
/// real-time preview, and bidirectional hexadecimal text input.
class ColorPickerWidget extends StatefulWidget {
  const ColorPickerWidget({
    super.key,
    required this.controller,
    required this.labelText,
    this.errorText,
    this.isHighlighter = false,
    this.onColorChanged,
  });

  final TextEditingController controller;
  final String labelText;
  final String? errorText;
  final bool isHighlighter;
  final ValueChanged<int>? onColorChanged;

  static const List<int> defaultPalette = [
    0xff202d46, // Ink (Blanko brand)
    0xff000000, // Black
    0xffffffff, // White
    0xff64748b, // Slate
    0xffdc2626, // Red
    0xffea580c, // Orange
    0xfff59e0b, // Amber / Yellow
    0xff16a34a, // Green
    0xff0d9488, // Teal
    0xff2563eb, // Origin Blue
    0xff7c3aed, // Purple
    0xffdb2777, // Pink
  ];

  static const List<int> highlighterPalette = [
    0xffffd54f, // Yellow highlighter
    0xff86efac, // Mint green
    0xff93c5fd, // Sky blue
    0xfff472b6, // Pink
    0xfffdba74, // Peach
    0xffc084fc, // Lavender
    0xfffde047, // Bright yellow
    0xff202d46, // Ink
  ];

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  late HSVColor _hsv;
  late int _currentColor;
  bool _showCustomSliders = false;

  static int parseHex(String text, int fallback) {
    final clean = text.trim().replaceFirst('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(clean)) {
      return 0xff000000 | int.parse(clean, radix: 16);
    }
    return fallback;
  }

  static String hexString(int value) =>
      (value & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase();

  static int _intFromHsv(HSVColor hsv) {
    final c = hsv.toColor();
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    return 0xff000000 | (r << 16) | (g << 8) | b;
  }

  @override
  void initState() {
    super.initState();
    _currentColor = parseHex(
      widget.controller.text,
      widget.isHighlighter ? 0xffffd54f : 0xff202d46,
    );
    _hsv = HSVColor.fromColor(Color(_currentColor));
    widget.controller.addListener(_onControllerTextChanged);
  }

  @override
  void didUpdateWidget(covariant ColorPickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerTextChanged);
      widget.controller.addListener(_onControllerTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTextChanged);
    super.dispose();
  }

  void _onControllerTextChanged() {
    final parsed = parseHex(widget.controller.text, -1);
    if (parsed != -1 && (parsed & 0xffffff) != (_currentColor & 0xffffff)) {
      setState(() {
        _currentColor = parsed;
        _hsv = HSVColor.fromColor(Color(parsed));
      });
      widget.onColorChanged?.call(_currentColor);
    }
  }

  void _setColor(int color, {bool updateHsv = true}) {
    setState(() {
      _currentColor = color;
      if (updateHsv) {
        _hsv = HSVColor.fromColor(Color(color));
      }
    });
    final hex = hexString(color);
    if (widget.controller.text.toUpperCase() != hex) {
      widget.controller.text = hex;
    }
    widget.onColorChanged?.call(color);
  }

  void _onHueChanged(double hue) {
    var sat = _hsv.saturation;
    var val = _hsv.value;
    if (sat < 0.15) sat = 0.85;
    if (val < 0.2) val = 0.9;
    final newHsv = HSVColor.fromAHSV(1.0, hue, sat, val);
    _hsv = newHsv;
    _setColor(_intFromHsv(newHsv), updateHsv: false);
  }

  void _onSaturationChanged(double sat) {
    final newHsv = _hsv.withSaturation(sat);
    _hsv = newHsv;
    _setColor(_intFromHsv(newHsv), updateHsv: false);
  }

  void _onValueChanged(double val) {
    final newHsv = _hsv.withValue(val);
    _hsv = newHsv;
    _setColor(_intFromHsv(newHsv), updateHsv: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = widget.isHighlighter
        ? ColorPickerWidget.highlighterPalette
        : ColorPickerWidget.defaultPalette;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with title and preview chip
        Row(
          children: [
            Expanded(
              child: Text(
                widget.labelText.replaceAll(' (RRGGBB)', ''),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Live color preview badge
            Tooltip(
              message: '#${hexString(_currentColor)}',
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(_currentColor),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.white24 : Colors.black12,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Toggle for custom hue/saturation sliders
            IconButton(
              icon: Icon(
                _showCustomSliders ? Icons.tune : Icons.color_lens_outlined,
                size: 20,
              ),
              tooltip: _showCustomSliders ? 'Hide sliders' : 'Custom color picker',
              onPressed: () =>
                  setState(() => _showCustomSliders = !_showCustomSliders),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Preset Swatches Grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in palette)
              _buildSwatch(color, theme),
          ],
        ),

        // Custom Visual Sliders (Spectrum / Hue, Saturation, Value)
        if (_showCustomSliders) ...[
          const SizedBox(height: 12),
          Text(
            'Hue: ${_hsv.hue.round()}°',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: const _GradientSliderTrackShape(
                gradient: LinearGradient(
                  colors: [
                    Color(0xffff0000),
                    Color(0xffffff00),
                    Color(0xff00ff00),
                    Color(0xff00ffff),
                    Color(0xff0000ff),
                    Color(0xffff00ff),
                    Color(0xffff0000),
                  ],
                ),
              ),
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              min: 0,
              max: 360,
              value: _hsv.hue.clamp(0, 360),
              onChanged: _onHueChanged,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saturation: ${(_hsv.saturation * 100).round()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Slider(
                      value: _hsv.saturation.clamp(0.0, 1.0),
                      onChanged: _onSaturationChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Brightness: ${(_hsv.value * 100).round()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Slider(
                      value: _hsv.value.clamp(0.0, 1.0),
                      onChanged: _onValueChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 8),

        // Hex Code Option (Kept fully compatible with automated tests and power users)
        TextField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: widget.labelText,
            prefixText: '#',
            errorText: widget.errorText,
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.colorize, size: 18),
              tooltip: _showCustomSliders ? 'Sliders open' : 'Open color picker sliders',
              onPressed: () =>
                  setState(() => _showCustomSliders = !_showCustomSliders),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwatch(int color, ThemeData theme) {
    final isSelected = (_currentColor & 0xffffff) == (color & 0xffffff);
    final swatchColor = Color(color);
    final isDarkColor =
        ThemeData.estimateBrightnessForColor(swatchColor) == Brightness.dark;

    return InkWell(
      onTap: () => _setColor(color),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: swatchColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (color == 0xffffffff
                    ? Colors.black26
                    : Colors.transparent),
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? Center(
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: isDarkColor ? Colors.white : Colors.black,
                ),
              )
            : null,
      ),
    );
  }
}

class _GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  const _GradientSliderTrackShape({required this.gradient});
  final LinearGradient gradient;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final paint = Paint()
      ..shader = gradient.createShader(trackRect)
      ..style = PaintingStyle.fill;
    final radius = Radius.circular(trackRect.height / 2);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      paint,
    );
  }
}
