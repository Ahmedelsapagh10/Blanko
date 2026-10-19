import 'dart:convert';

import '../geometry/geometry.dart';
import 'document.dart';
import 'document_geometry.dart';
import 'document_settings.dart';
import 'element.dart';

/// Portable, versioned snapshots. No renderer resources or undo history persist.
/// Limits bound malformed-input work while retaining scenes above 10K elements.
final class DocumentCodec {
  static const maximumBytes = 64 * 1024 * 1024;
  static const maximumElements = 100000;
  static const maximumStrokePoints = 2000000;
  static const _maximumNumber = 9007199254740991;

  static String encode(BoardDocument document) {
    _validate(document);
    final value = <String, Object?>{
      'format': 'whiteboard.document',
      'schemaVersion': document.schemaVersion,
      'id': document.id,
      'workspaceId': document.workspaceId,
      'revision': document.revision,
      'title': document.title,
      'canvas': {
        'backgroundColor': document.canvasSettings.backgroundColor,
        'grid': {
          'visible': document.canvasSettings.grid.visible,
          'spacing': document.canvasSettings.grid.spacing,
          'color': document.canvasSettings.grid.color,
        },
      },
      'assets': [
        for (final asset in document.assets!)
          {
            'id': asset.id,
            'mimeType': asset.mimeType,
            'pixelWidth': asset.pixelWidth,
            'pixelHeight': asset.pixelHeight,
            'byteLength': asset.byteLength,
            'sha256': asset.sha256,
          },
      ],
      'fontReferences': [
        for (final font in document.fontReferences!)
          {'id': font.id, 'family': font.family, 'assetId': font.assetId},
      ],
      'metadata': switch (document.metadata) {
        null => null,
        final metadata => {
          'createdAt': metadata.createdAt.toIso8601String(),
          'modifiedAt': metadata.modifiedAt.toIso8601String(),
          'createdWithVersion': metadata.createdWithVersion,
          'modifiedWithVersion': metadata.modifiedWithVersion,
          'minimumReaderVersion': metadata.minimumReaderVersion,
        },
      },
      // Source order, rather than a derived traversal, defines sibling z-order.
      'elements': [
        for (final element in document.elements)
          {
            'id': element.id.value,
            'parentId': element.parentId?.value,
            'revision': element.revision,
            'locked': element.locked,
            'opacity': element.opacity,
            'transform': [
              element.transform.a,
              element.transform.b,
              element.transform.c,
              element.transform.d,
              element.transform.tx,
              element.transform.ty,
            ],
            'content': _encodeContent(element.content),
          },
      ],
    };
    _validateNumbers(value);
    final source = jsonEncode(value);
    _size(source);
    return source;
  }

  static BoardDocument decode(String source) {
    try {
      _size(source);
      _preflight(source);
      final value = jsonDecode(source);
      _validateNumbers(value);
      final root = _object(value, [
        'format',
        'schemaVersion',
        'id',
        'workspaceId',
        'revision',
        'title',
        'canvas',
        'assets',
        'fontReferences',
        'metadata',
        'elements',
      ]);
      if (root['format'] != 'whiteboard.document' ||
          _integer(root['schemaVersion']) != BoardDocument.currentVersion) {
        throw const FormatException('Unsupported document format or version.');
      }
      final canvas = _object(root['canvas'], ['backgroundColor', 'grid']);
      final grid = _object(canvas['grid'], ['visible', 'spacing', 'color']);
      final values = _list(root['elements']);
      if (values.length > maximumElements) {
        throw const FormatException('Document exceeds element limit.');
      }
      var pointCount = 0;
      final elements = <DocumentElement>[];
      for (final value in values) {
        final element = _object(value, [
          'id',
          'parentId',
          'revision',
          'locked',
          'opacity',
          'transform',
          'content',
        ]);
        final content = _decodeContent(element['content']);
        if (content is StrokeElementContent) {
          pointCount += content.points.length;
          if (pointCount > maximumStrokePoints) {
            throw const FormatException('Document exceeds stroke point limit.');
          }
        }
        final transform = _list(element['transform'], length: 6);
        elements.add(
          DocumentElement(
            id: ElementId(_string(element['id'])),
            parentId: element['parentId'] == null
                ? null
                : ElementId(_string(element['parentId'])),
            revision: _integer(element['revision']),
            locked: _boolean(element['locked']),
            opacity: _number(element['opacity']),
            transform: Transform2(
              a: _number(transform[0]),
              b: _number(transform[1]),
              c: _number(transform[2]),
              d: _number(transform[3]),
              tx: _number(transform[4]),
              ty: _number(transform[5]),
            ),
            content: content,
          ),
        );
      }
      final document = BoardDocument(
        id: _string(root['id']),
        workspaceId: _nullableString(root['workspaceId']),
        schemaVersion: _integer(root['schemaVersion']),
        revision: _integer(root['revision']),
        title: _string(root['title']),
        canvasSettings: CanvasSettings(
          backgroundColor: _integer(canvas['backgroundColor']),
          grid: GridSettings(
            visible: _boolean(grid['visible']),
            spacing: _number(grid['spacing']),
            color: _integer(grid['color']),
          ),
        ),
        assets: [
          for (final value in _list(root['assets'])) _decodeAsset(value),
        ],
        fontReferences: [
          for (final value in _list(root['fontReferences'])) _decodeFont(value),
        ],
        metadata: _decodeMetadata(root['metadata']),
        elements: elements,
      );
      _validate(document);
      return document;
    } on ArgumentError catch (error) {
      throw FormatException('Invalid document: ${error.message}');
    }
  }

  static Map<String, Object?> _encodeContent(ElementContent content) {
    final result = <String, Object?>{};
    switch (content) {
      case ShapeElementContent():
        result.addAll({
          'type': 'shape',
          'kind': content.kind.name,
          'bounds': _bounds(content.bounds),
          'fillColor': content.fillColor,
          'stroke': content.stroke == null ? null : _stroke(content.stroke!),
        });
      case StrokeElementContent():
        result.addAll({
          'type': 'stroke',
          'kind': content.kind.name,
          'points': [for (final point in content.points) _point(point)],
          'style': _stroke(content.style),
        });
      case LineElementContent():
        result.addAll({
          'type': 'line',
          'start': _point(content.start),
          'end': _point(content.end),
          'style': _stroke(content.style),
        });
      case ArrowElementContent():
        result.addAll({
          'type': 'arrow',
          'start': _point(content.start),
          'end': _point(content.end),
          'style': _stroke(content.style),
          'headLength': content.headLength,
          'headWidth': content.headWidth,
        });
      case TextElementContent():
        result.addAll({
          'type': 'text',
          'text': content.text,
          'bounds': _bounds(content.bounds),
          'style': _textStyle(content.style),
          'direction': content.direction.name,
          'alignment': content.alignment.name,
          'sizing': content.sizing.name,
        });
      case StickyNoteElementContent():
        result.addAll({
          'type': 'stickyNote',
          'text': content.text,
          'bounds': _bounds(content.bounds),
          'style': _textStyle(content.style),
          'direction': content.direction.name,
          'alignment': content.alignment.name,
          'sizing': content.sizing.name,
          'backgroundColor': content.backgroundColor,
        });
      case ImageElementContent():
        result.addAll({
          'type': 'image',
          'assetId': content.assetId,
          'bounds': _bounds(content.bounds),
        });
      case GroupElementContent():
        result['type'] = 'group';
      case ExportFrameElementContent():
        result.addAll({
          'type': 'exportFrame',
          'bounds': _bounds(content.bounds),
          'label': content.label,
        });
      case ContainerFrameElementContent():
        result.addAll({
          'type': 'containerFrame',
          'bounds': _bounds(content.bounds),
          'label': content.label,
        });
    }
    return result;
  }

  static ElementContent _decodeContent(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected content object.');
    }
    final type = _string(value['type']);
    final keys = switch (type) {
      'shape' => ['kind', 'bounds', 'fillColor', 'stroke'],
      'stroke' => ['kind', 'points', 'style'],
      'line' => ['start', 'end', 'style'],
      'arrow' => ['start', 'end', 'style', 'headLength', 'headWidth'],
      'text' => ['text', 'bounds', 'style', 'direction', 'alignment', 'sizing'],
      'stickyNote' => [
        'text',
        'bounds',
        'style',
        'direction',
        'alignment',
        'sizing',
        'backgroundColor',
      ],
      'image' => ['assetId', 'bounds'],
      'group' => <String>[],
      'exportFrame' || 'containerFrame' => ['bounds', 'label'],
      _ => throw FormatException('Unsupported content type: $type'),
    };
    final map = _object(value, ['type', ...keys]);
    return switch (type) {
      'shape' => ShapeElementContent(
        kind: _enum(map['kind'], ShapeKind.values),
        bounds: _readBounds(map['bounds']),
        fillColor: map['fillColor'] == null ? null : _integer(map['fillColor']),
        stroke: map['stroke'] == null ? null : _readStroke(map['stroke']),
      ),
      'stroke' => StrokeElementContent(
        kind: _enum(map['kind'], StrokeKind.values),
        points: _readPoints(map['points']),
        style: _readStroke(map['style']),
      ),
      'line' => LineElementContent(
        start: _readPoint(map['start']),
        end: _readPoint(map['end']),
        style: _readStroke(map['style']),
      ),
      'arrow' => ArrowElementContent(
        start: _readPoint(map['start']),
        end: _readPoint(map['end']),
        style: _readStroke(map['style']),
        headLength: _number(map['headLength']),
        headWidth: _number(map['headWidth']),
      ),
      'text' => TextElementContent(
        text: _string(map['text']),
        bounds: _readBounds(map['bounds']),
        style: _readTextStyle(map['style']),
        direction: _enum(map['direction'], ElementTextDirection.values),
        alignment: _enum(map['alignment'], ElementTextAlignment.values),
        sizing: _enum(map['sizing'], TextSizing.values),
      ),
      'stickyNote' => StickyNoteElementContent(
        text: _string(map['text']),
        bounds: _readBounds(map['bounds']),
        style: _readTextStyle(map['style']),
        direction: _enum(map['direction'], ElementTextDirection.values),
        alignment: _enum(map['alignment'], ElementTextAlignment.values),
        sizing: _enum(map['sizing'], TextSizing.values),
        backgroundColor: _integer(map['backgroundColor']),
      ),
      'image' => ImageElementContent(
        assetId: _string(map['assetId']),
        bounds: _readBounds(map['bounds']),
      ),
      'group' => const GroupElementContent(),
      'exportFrame' => ExportFrameElementContent(
        bounds: _readBounds(map['bounds']),
        label: _string(map['label']),
      ),
      'containerFrame' => ContainerFrameElementContent(
        bounds: _readBounds(map['bounds']),
        label: _string(map['label']),
      ),
      _ => throw const FormatException('Unsupported content.'),
    };
  }

  static DocumentAssetReference _decodeAsset(Object? value) {
    final map = _object(value, [
      'id',
      'mimeType',
      'pixelWidth',
      'pixelHeight',
      'byteLength',
      'sha256',
    ]);
    return DocumentAssetReference(
      id: _string(map['id']),
      mimeType: _string(map['mimeType']),
      pixelWidth: map['pixelWidth'] == null
          ? null
          : _integer(map['pixelWidth']),
      pixelHeight: map['pixelHeight'] == null
          ? null
          : _integer(map['pixelHeight']),
      byteLength: map['byteLength'] == null
          ? null
          : _integer(map['byteLength']),
      sha256: _nullableString(map['sha256']),
    );
  }

  static DocumentFontReference _decodeFont(Object? value) {
    final map = _object(value, ['id', 'family', 'assetId']);
    return DocumentFontReference(
      id: _string(map['id']),
      family: _string(map['family']),
      assetId: _nullableString(map['assetId']),
    );
  }

  static DocumentMetadata? _decodeMetadata(Object? value) {
    if (value == null) return null;
    final map = _object(value, [
      'createdAt',
      'modifiedAt',
      'createdWithVersion',
      'modifiedWithVersion',
      'minimumReaderVersion',
    ]);
    return DocumentMetadata(
      createdAt: _date(map['createdAt']),
      modifiedAt: _date(map['modifiedAt']),
      createdWithVersion: _nullableString(map['createdWithVersion']),
      modifiedWithVersion: _nullableString(map['modifiedWithVersion']),
      minimumReaderVersion: _integer(map['minimumReaderVersion']),
    );
  }

  static DateTime _date(Object? value) {
    final text = _string(value);
    final date = DateTime.tryParse(text);
    if (date == null || date.toUtc().toIso8601String() != text) {
      throw const FormatException('Expected canonical UTC timestamp.');
    }
    return date;
  }

  static void _validate(BoardDocument document) {
    if (document.assets == null || document.fontReferences == null) {
      throw const FormatException(
        'Persistence requires complete asset and font manifests.',
      );
    }
    if (document.elements.length > maximumElements) {
      throw const FormatException('Document exceeds element limit.');
    }
    final geometry = DocumentGeometry(document);
    var points = 0;
    for (final element in document.elements) {
      final content = element.content;
      final bounds = switch (content) {
        ShapeElementContent(:final bounds) ||
        TextElementContent(:final bounds) ||
        StickyNoteElementContent(:final bounds) ||
        ImageElementContent(:final bounds) ||
        ExportFrameElementContent(:final bounds) ||
        ContainerFrameElementContent(:final bounds) => bounds,
        StrokeElementContent(:final points) => Bounds2.fromPoints(points),
        LineElementContent(:final start, :final end) ||
        ArrowElementContent(
          :final start,
          :final end,
        ) => Bounds2.fromPoints([start, end]),
        GroupElementContent() => null,
      };
      if (bounds != null) {
        geometry.worldTransformOf(element.id).mapBounds(bounds);
      }
      if (content is StrokeElementContent) points += content.points.length;
      if (points > maximumStrokePoints) {
        throw const FormatException('Document exceeds stroke point limit.');
      }
    }
  }

  static List<double> _point(Point2 point) => [point.x, point.y];
  static List<double> _bounds(Bounds2 bounds) => [
    bounds.left,
    bounds.top,
    bounds.right,
    bounds.bottom,
  ];
  static Map<String, Object> _stroke(StrokeStyle style) => {
    'color': style.color,
    'width': style.width,
  };
  static Map<String, Object> _textStyle(ElementTextStyle style) => {
    'fontId': style.fontId,
    'fontSize': style.fontSize,
    'color': style.color,
  };
  static Point2 _readPoint(Object? value) {
    final values = _list(value, length: 2);
    return Point2(_number(values[0]), _number(values[1]));
  }

  static Bounds2 _readBounds(Object? value) {
    final values = _list(value, length: 4);
    return Bounds2(
      _number(values[0]),
      _number(values[1]),
      _number(values[2]),
      _number(values[3]),
    );
  }

  static List<Point2> _readPoints(Object? value) {
    final values = _list(value);
    if (values.length > maximumStrokePoints) {
      throw const FormatException('Stroke exceeds point limit.');
    }
    return [for (final value in values) _readPoint(value)];
  }

  static StrokeStyle _readStroke(Object? value) {
    final map = _object(value, ['color', 'width']);
    return StrokeStyle(
      color: _integer(map['color']),
      width: _number(map['width']),
    );
  }

  static ElementTextStyle _readTextStyle(Object? value) {
    final map = _object(value, ['fontId', 'fontSize', 'color']);
    return ElementTextStyle(
      fontId: _string(map['fontId']),
      fontSize: _number(map['fontSize']),
      color: _integer(map['color']),
    );
  }

  static Map<String, dynamic> _object(Object? value, List<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const FormatException('Object has missing or unsupported fields.');
    }
    return value;
  }

  static List<dynamic> _list(Object? value, {int? length}) {
    if (value is! List<dynamic> || (length != null && value.length != length)) {
      throw const FormatException('Expected array with valid length.');
    }
    return value;
  }

  static String _string(Object? value) =>
      value is String ? value : throw const FormatException('Expected string.');
  static String? _nullableString(Object? value) =>
      value == null ? null : _string(value);
  static bool _boolean(Object? value) =>
      value is bool ? value : throw const FormatException('Expected boolean.');
  static int _integer(Object? value) =>
      value is int && value >= -_maximumNumber && value <= _maximumNumber
      ? value
      : throw const FormatException('Expected safe integer.');
  static double _number(Object? value) =>
      value is num &&
          value.isFinite &&
          value >= -_maximumNumber &&
          value <= _maximumNumber
      ? value.toDouble()
      : throw const FormatException('Expected finite safe numeric value.');
  static T _enum<T extends Enum>(Object? value, List<T> values) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    throw const FormatException('Unsupported enum value.');
  }

  static void _size(String source) {
    if (source.length > maximumBytes ||
        utf8.encode(source).length > maximumBytes) {
      throw const FormatException('Document exceeds 64 MiB snapshot limit.');
    }
  }

  static void _validateNumbers(Object? value) {
    switch (value) {
      case num():
        _number(value);
      case List():
        for (final child in value) {
          _validateNumbers(child);
        }
      case Map():
        for (final child in value.values) {
          _validateNumbers(child);
        }
    }
  }

  // Reject duplicate fields and excessive nesting before the platform JSON
  // decoder can overwrite a field or recurse on malicious input.
  static void _preflight(String source) {
    final objects = <Set<String>?>[];
    final expectingKeys = <bool>[];
    for (var i = 0; i < source.length; i++) {
      final code = source.codeUnitAt(i);
      if (code == 34) {
        final start = i;
        var escaped = false;
        for (i++; i < source.length; i++) {
          final next = source.codeUnitAt(i);
          if (!escaped && next == 34) break;
          if (!escaped && next == 92) {
            escaped = true;
          } else {
            escaped = false;
          }
        }
        if (i >= source.length) {
          throw const FormatException('Unterminated string.');
        }
        if (objects.isNotEmpty && expectingKeys.last && objects.last != null) {
          final key = jsonDecode(source.substring(start, i + 1)) as String;
          if (!objects.last!.add(key)) {
            throw const FormatException('Duplicate object field.');
          }
          expectingKeys[expectingKeys.length - 1] = false;
        }
      } else if (code == 123 || code == 91) {
        objects.add(code == 123 ? <String>{} : null);
        expectingKeys.add(code == 123);
        if (objects.length > 32) {
          throw const FormatException('Excessive JSON nesting.');
        }
      } else if (code == 125 || code == 93) {
        if (objects.isEmpty) throw const FormatException('Unbalanced JSON.');
        objects.removeLast();
        expectingKeys.removeLast();
      } else if (code == 44 && objects.isNotEmpty && objects.last != null) {
        expectingKeys[expectingKeys.length - 1] = true;
      }
    }
  }
}
