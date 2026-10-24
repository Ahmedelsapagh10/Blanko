import 'dart:convert';

/// A bounded, insert-only Quill snapshot. UI controllers and selection stay out
/// of document state. Unsupported content is rejected rather than flattened.
final class RichTextData {
  RichTextData._(this.delta, this.plainText);

  static const version = 1;
  static const maximumOperations = 100000;
  static const maximumTextLength = 1000000;
  static const _inlineFlags = {'bold', 'italic', 'underline', 'strike'};
  static const _paragraph = {'align', 'direction', 'list'};
  static final _color = RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');
  static final _control = RegExp(r'[\x00-\x20\x7f]');

  /// Deeply immutable operations, including their attributes maps.
  final List<Map<String, Object?>> delta;

  /// The editor's content, excluding Quill's mandatory terminating newline.
  final String plainText;

  factory RichTextData.fromJson(Object? value) {
    final root = _map(value);
    if (root.length != 2 ||
        root['version'] != version ||
        !root.containsKey('delta')) {
      throw const FormatException('Unsupported rich text snapshot.');
    }
    final source = root['delta'];
    if (source is! List ||
        source.isEmpty ||
        source.length > maximumOperations) {
      throw const FormatException('Invalid rich text operation count.');
    }
    final result = <Map<String, Object?>>[];
    final text = StringBuffer();
    var length = 0;
    String? previousAttributes;
    var pending = StringBuffer();
    Map<String, Object?> pendingAttributes = const {};
    void flush() {
      if (pending.isEmpty) return;
      result.add(
        Map<String, Object?>.unmodifiable({
          'insert': pending.toString(),
          if (pendingAttributes.isNotEmpty)
            'attributes': Map<String, Object?>.unmodifiable(pendingAttributes),
        }),
      );
      pending = StringBuffer();
    }

    for (final value in source) {
      final op = _map(value);
      if (op.keys.any((key) => key != 'insert' && key != 'attributes')) {
        throw const FormatException('Rich text only supports text insertions.');
      }
      final insert = op['insert'];
      if (insert is! String || insert.isEmpty) {
        throw const FormatException(
          'Rich text insertions must be nonempty text.',
        );
      }
      length += insert.length;
      if (length > maximumTextLength) {
        throw const FormatException('Rich text exceeds text length limit.');
      }
      final attributes = <String, Object?>{};
      if (op.containsKey('attributes')) {
        final sourceAttributes = _map(op['attributes']);
        final keys = sourceAttributes.keys.toList()..sort();
        for (final key in keys) {
          final attribute = sourceAttributes[key];
          if (_paragraph.contains(key) &&
              insert.runes.any((character) => character != 10)) {
            throw const FormatException(
              'Paragraph attributes require newlines.',
            );
          }
          attributes[key] = _attribute(key, attribute);
        }
      }
      final encodedAttributes = jsonEncode(attributes);
      if (previousAttributes != encodedAttributes) {
        flush();
        pendingAttributes = attributes;
      }
      pending.write(insert);
      previousAttributes = encodedAttributes;
      text.write(insert);
    }
    flush();
    final content = text.toString();
    if (!content.endsWith('\n')) {
      throw const FormatException('Rich text requires a final newline.');
    }
    return RichTextData._(
      List.unmodifiable(result),
      content.substring(0, content.length - 1),
    );
  }

  Map<String, Object?> toJson() => {'version': version, 'delta': delta};

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Expected a rich text object.');
    }
    return Map<String, Object?>.from(value);
  }

  static Object _attribute(String key, Object? value) {
    if (_inlineFlags.contains(key) && value == true) return true;
    if (key == 'font' && (value == 'Roboto' || value == 'Noto Sans Arabic')) {
      return value!;
    }
    if (key == 'size' && (value is num || value is String)) {
      final size = value is num
          ? value.toDouble()
          : double.tryParse(value as String);
      if (size != null && size.isFinite && size >= 8 && size <= 144) {
        return size == size.roundToDouble()
            ? size.toInt().toString()
            : size.toString();
      }
    }
    if ((key == 'color' || key == 'background') &&
        value is String &&
        _color.hasMatch(value)) {
      return value.toUpperCase();
    }
    if (key == 'link' &&
        value is String &&
        value.length <= 2048 &&
        !_control.hasMatch(value)) {
      final uri = Uri.tryParse(value);
      if (uri != null &&
          (({'https', 'http'}.contains(uri.scheme) &&
                  uri.host.isNotEmpty &&
                  uri.userInfo.isEmpty) ||
              (uri.scheme == 'mailto' && uri.path.isNotEmpty))) {
        return value;
      }
    }
    if (key == 'align' &&
        {'left', 'center', 'right', 'justify'}.contains(value)) {
      return value!;
    }
    if (key == 'direction' && {'rtl', 'ltr'}.contains(value)) return value!;
    if (key == 'list' && {'bullet', 'ordered'}.contains(value)) return value!;
    throw FormatException('Unsupported rich text attribute: $key.');
  }
}
