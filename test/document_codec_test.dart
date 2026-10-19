import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

final _bounds = Bounds2(-10.25, -20.5, 150.75, 200.125);
final _stroke = StrokeStyle(color: 0x804080ff, width: 3.25);
final _textStyle = ElementTextStyle(
  fontId: 'arabic',
  fontSize: 25.25,
  color: 0xff012345,
);

BoardDocument _fixture() {
  final contents = <ElementContent>[
    ShapeElementContent(
      kind: ShapeKind.triangle,
      bounds: _bounds,
      fillColor: 0x40abcdef,
      stroke: _stroke,
    ),
    StrokeElementContent(
      points: [Point2(-100, 200), Point2(1.25, -3.5)],
      kind: StrokeKind.highlighter,
      style: _stroke,
    ),
    LineElementContent(
      start: Point2(-1, 2),
      end: Point2(300, 400),
      style: _stroke,
    ),
    ArrowElementContent(
      start: Point2(1, 2),
      end: Point2(9, 20),
      style: _stroke,
      headLength: 7.5,
      headWidth: 8.25,
    ),
    TextElementContent(
      text: 'مرحبا بالعالم 👋\nEnglish "quoted" \\ text',
      bounds: _bounds,
      style: _textStyle,
      direction: ElementTextDirection.rtl,
      alignment: ElementTextAlignment.end,
      sizing: TextSizing.fixed,
    ),
    StickyNoteElementContent(
      text: 'ملاحظة',
      bounds: _bounds,
      style: _textStyle,
      backgroundColor: 0x80ffff00,
      direction: ElementTextDirection.auto,
      alignment: ElementTextAlignment.center,
      sizing: TextSizing.autoHeight,
    ),
    ImageElementContent(assetId: 'image', bounds: _bounds),
    const GroupElementContent(),
    ExportFrameElementContent(bounds: _bounds, label: 'Export عربي'),
    ContainerFrameElementContent(bounds: _bounds, label: 'Container'),
  ];
  return BoardDocument(
    id: 'board-عربي',
    workspaceId: 'local-board-123',
    title: 'My board 🖊️',
    revision: 42,
    canvasSettings: CanvasSettings(
      backgroundColor: 0xff123456,
      grid: GridSettings(visible: true, spacing: 35.125, color: 0x30aabbcc),
    ),
    assets: [
      DocumentAssetReference(
        id: 'image',
        mimeType: 'image/png',
        pixelWidth: 1024,
        pixelHeight: 512,
        byteLength: 123456,
        sha256: 'a' * 64,
      ),
      DocumentAssetReference(
        id: 'font-asset',
        mimeType: 'font/ttf',
        byteLength: 7654,
      ),
    ],
    fontReferences: [
      DocumentFontReference(
        id: 'arabic',
        family: 'Noto Sans Arabic',
        assetId: 'font-asset',
      ),
    ],
    metadata: DocumentMetadata(
      createdAt: DateTime.utc(2026, 10, 19, 2, 4, 6, 123, 456),
      modifiedAt: DateTime.utc(2026, 10, 20),
      createdWithVersion: '0.1.0',
      modifiedWithVersion: '0.2.0',
    ),
    elements: [
      // Child precedes parent in source order: codec must not serialize preorder.
      for (var i = 0; i < contents.length; i++)
        DocumentElement(
          id: ElementId('e$i'),
          parentId: i == 0 ? ElementId('e7') : null,
          revision: i,
          locked: i == 2,
          opacity: (i + 1) / 10,
          transform: Transform2(
            a: 1.25,
            b: 0.125,
            c: 0.5,
            d: -2.5,
            tx: i * 123.25,
            ty: -i * 31.5,
          ),
          content: contents[i],
        ),
    ],
  );
}

Map<String, dynamic> _snapshot() =>
    jsonDecode(DocumentCodec.encode(_fixture())) as Map<String, dynamic>;
void _reject(void Function(Map<String, dynamic>) change) {
  final map = _snapshot();
  change(map);
  expect(() => DocumentCodec.decode(jsonEncode(map)), throwsFormatException);
}

void main() {
  test(
    'round trip every content field, styles, RTL, hierarchy and metadata',
    () {
      final original = _fixture();
      final source = DocumentCodec.encode(original);
      final restored = DocumentCodec.decode(source);
      expect(DocumentCodec.encode(restored), source);
      expect(
        restored.elements.map((element) => element.id.value),
        original.elements.map((element) => element.id.value),
      );
      expect(restored.elements.first.parentId, ElementId('e7'));
      expect(restored.preorder.first.id, ElementId('e1'));
      expect(restored.workspaceId, original.workspaceId);
      expect(restored.metadata!.createdAt, original.metadata!.createdAt);
      expect(restored.assets!.first.sha256, 'a' * 64);
      expect(restored.elements[4].content, isA<TextElementContent>());
      expect(
        (restored.elements[4].content as TextElementContent).text,
        (original.elements[4].content as TextElementContent).text,
      );
    },
  );

  test('empty authoritative manifests and null metadata remain exact', () {
    final source = DocumentCodec.encode(
      BoardDocument(
        id: 'empty',
        revision: 0,
        elements: const [],
        assets: const [],
        fontReferences: const [],
      ),
    );
    final document = DocumentCodec.decode(source);
    expect(document.assets, isEmpty);
    expect(document.fontReferences, isEmpty);
    expect(document.metadata, isNull);
    expect(DocumentCodec.encode(document), source);
  });

  test('unresolved manifests cannot be persisted or loaded', () {
    expect(
      () => DocumentCodec.encode(
        BoardDocument(id: 'unresolved', revision: 0, elements: const []),
      ),
      throwsFormatException,
    );
    _reject((map) => map['assets'] = null);
    _reject((map) => map['fontReferences'] = null);
    _reject((map) => map.remove('assets'));
  });

  test(
    'unsupported schema, format, content and enums fail without data loss',
    () {
      _reject((map) => map['schemaVersion'] = 2);
      _reject((map) => map['format'] = 'unknown');
      _reject((map) => map['elements'][0]['content']['type'] = 'video');
      _reject((map) => map['elements'][0]['content']['kind'] = 'future-shape');
    },
  );

  test('unknown or missing nested fields are rejected', () {
    _reject((map) => map['future'] = 1);
    _reject((map) => map['canvas']['future'] = true);
    _reject((map) => map['elements'][0]['content']['stroke']['dash'] = [1, 2]);
    _reject((map) => map['elements'][0].remove('opacity'));
    _reject((map) => map['assets'][0]['newAssetField'] = 'not discarded');
    _reject((map) => map['metadata']['newMetadata'] = true);
  });

  test(
    'corrupt, truncated, duplicate and excessively nested JSON rejected',
    () {
      for (final source in [
        '{',
        'null',
        '[]',
        '"hello"',
        '{"a":1,"a":2}',
        '{"a":1,"\\u0061":2}',
        '${'[' * 33}0${']' * 33}',
      ]) {
        expect(() => DocumentCodec.decode(source), throwsFormatException);
      }
    },
  );

  test('unsafe numbers and wrong scalar types rejected', () {
    _reject((map) => map['revision'] = 9007199254740992);
    _reject((map) => map['elements'][0]['transform'][4] = -9223372036854775808);
    _reject((map) => map['revision'] = 1.5);
    _reject((map) => map['elements'][0]['transform'][4] = 9007199254740992);
    _reject((map) => map['canvas']['grid']['visible'] = 'true');
    _reject((map) => map['elements'][0]['transform'] = [1, 2]);
    final source = DocumentCodec.encode(_fixture());
    expect(
      () => DocumentCodec.decode(source.replaceFirst('123.25', '1e999')),
      throwsFormatException,
    );
  });

  test('invalid document ownership, transforms and references rejected', () {
    _reject((map) => map['elements'][0]['parentId'] = 'missing');
    _reject((map) => map['elements'][7]['parentId'] = 'e7');
    _reject((map) => map['elements'][1]['id'] = 'e0');
    _reject((map) => map['elements'][1]['revision'] = 43);
    _reject((map) => map['elements'][0]['transform'] = [0, 0, 0, 0, 0, 0]);
    _reject((map) => map['assets'] = []);
    _reject((map) => map['fontReferences'] = []);
  });

  test('timestamp overflow and future minimum reader version rejected', () {
    _reject((map) => map['metadata']['createdAt'] = '2026-02-31T00:00:00.000Z');
    _reject(
      (map) => map['metadata']['modifiedAt'] = '2025-01-01T00:00:00.000Z',
    );
    _reject((map) => map['metadata']['minimumReaderVersion'] = 2);
  });

  test('10K elements and large-world fractional transforms round trip', () {
    final document = BoardDocument(
      id: 'large',
      revision: maximumDocumentRevision,
      assets: const [],
      fontReferences: const [],
      elements: [
        for (var i = 0; i < 10001; i++)
          DocumentElement(
            id: ElementId('shape$i'),
            revision: maximumDocumentRevision,
            transform: Transform2.translation(
              1000000000.125 - i,
              -1000000000.25 + i,
            ),
            content: ShapeElementContent(
              kind: ShapeKind.rectangle,
              bounds: _bounds,
              stroke: _stroke,
            ),
          ),
      ],
    );
    final source = DocumentCodec.encode(document);
    final restored = DocumentCodec.decode(source);
    expect(restored.elements.length, 10001);
    expect(restored.revision, maximumDocumentRevision);
    expect(
      restored.elements.first.transform,
      document.elements.first.transform,
    );
    expect(DocumentCodec.encode(restored), source);
  });

  test('element safety cap rejects before decoding individual elements', () {
    final map = _snapshot();
    map['elements'] = List.filled(DocumentCodec.maximumElements + 1, null);
    expect(() => DocumentCodec.decode(jsonEncode(map)), throwsFormatException);
  });

  test('encoded values outside safe range cannot publish a snapshot', () {
    final document = BoardDocument(
      id: 'unsafe',
      revision: 0,
      assets: const [],
      fontReferences: const [],
      elements: [
        DocumentElement(
          id: ElementId('shape'),
          transform: Transform2.translation(1e20, 0),
          content: ShapeElementContent(
            kind: ShapeKind.ellipse,
            bounds: _bounds,
            stroke: _stroke,
          ),
        ),
      ],
    );
    expect(() => DocumentCodec.encode(document), throwsFormatException);
  });
}
