import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

void main() {
  test(
    'canvas defaults are deterministic and settings reject invalid values',
    () {
      final defaults = CanvasSettings();
      expect(defaults.backgroundColor, 0xffffffff);
      expect(defaults.grid.visible, isFalse);
      expect(defaults.grid.spacing, 20);
      final grid = GridSettings(
        visible: true,
        spacing: 12.5,
        color: 0x80224466,
      );
      final settings = CanvasSettings(backgroundColor: 0, grid: grid);
      expect(settings.grid, same(grid));
      expect(settings.grid.color, 0x80224466);
      expect(settings.backgroundColor, 0);
      for (final value in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => GridSettings(spacing: value), throwsArgumentError);
      }
      for (final value in [-1, 0x100000000]) {
        expect(
          () => CanvasSettings(backgroundColor: value),
          throwsArgumentError,
        );
        expect(() => GridSettings(color: value), throwsArgumentError);
      }
    },
  );

  test(
    'asset descriptors retain dimensions and normalize declared digests',
    () {
      final image = DocumentAssetReference(
        id: 'original-image',
        mimeType: 'image/png',
        pixelWidth: 1024,
        pixelHeight: 768,
        byteLength: 4096,
        sha256: 'AB' * 32,
      );
      expect(image.pixelWidth, 1024);
      expect(image.pixelHeight, 768);
      expect(image.byteLength, 4096);
      expect(image.sha256, 'ab' * 32);
      final font = DocumentAssetReference(
        id: 'font-file',
        mimeType: 'font/ttf',
      );
      expect(font.pixelWidth, isNull);
      expect(font.pixelHeight, isNull);
      expect(font.sha256, isNull);
    },
  );

  test('asset descriptors reject malformed identity and sizes', () {
    DocumentAssetReference image({
      String id = 'image',
      String mimeType = 'image/png',
      int? width = 4,
      int? height = 8,
      int? bytes,
      String? digest,
    }) => DocumentAssetReference(
      id: id,
      mimeType: mimeType,
      pixelWidth: width,
      pixelHeight: height,
      byteLength: bytes,
      sha256: digest,
    );
    expect(() => image(id: '  '), throwsArgumentError);
    for (final type in [
      '',
      'image',
      'image/',
      'image/png; charset=utf8',
      ' / ',
      'image/png\n',
    ]) {
      expect(() => image(mimeType: type), throwsArgumentError);
    }
    expect(() => image(width: null), throwsArgumentError);
    expect(() => image(width: null, height: null), throwsArgumentError);
    for (final dimension in [0, -1, maximumDocumentRevision + 1]) {
      expect(() => image(width: dimension), throwsArgumentError);
      expect(() => image(height: dimension), throwsArgumentError);
    }
    for (final bytes in [0, -1, maximumDocumentRevision + 1]) {
      expect(() => image(bytes: bytes), throwsArgumentError);
    }
    for (final digest in ['', 'ab', 'z' * 64, '${'a' * 64}\n']) {
      expect(() => image(digest: digest), throwsArgumentError);
    }
  });

  test(
    'font identity does not imply an available or licensed font resource',
    () {
      final reference = DocumentFontReference(
        id: 'curated',
        family: 'Curated Family',
        assetId: 'font-original',
      );
      expect(reference.id, 'curated');
      expect(reference.family, 'Curated Family');
      expect(reference.assetId, 'font-original');
      expect(
        DocumentFontReference(id: 'system', family: 'System').assetId,
        isNull,
      );
      expect(
        () => DocumentFontReference(id: '', family: 'Family'),
        throwsArgumentError,
      );
      expect(
        () => DocumentFontReference(id: 'font', family: ' '),
        throwsArgumentError,
      );
      expect(
        () => DocumentFontReference(id: 'font', family: 'Family', assetId: ''),
        throwsArgumentError,
      );
    },
  );

  test('metadata preserves explicit instants and validates chronology', () {
    final created = DateTime.utc(2026, 10, 15, 10);
    final modified = created.add(const Duration(seconds: 5));
    final metadata = DocumentMetadata(
      createdAt: created.toLocal(),
      modifiedAt: modified.toLocal(),
      createdWithVersion: '1.0.0',
      modifiedWithVersion: '1.1.0',
    );
    expect(metadata.createdAt, created);
    expect(metadata.modifiedAt, modified);
    expect(metadata.createdAt.isUtc, isTrue);
    expect(metadata.modifiedAt.isUtc, isTrue);
    expect(metadata.createdWithVersion, '1.0.0');
    expect(metadata.modifiedWithVersion, '1.1.0');
    expect(metadata.minimumReaderVersion, 1);
    expect(
      () => DocumentMetadata(createdAt: modified, modifiedAt: created),
      throwsArgumentError,
    );
    for (final version in [0, -1, maximumDocumentRevision + 1]) {
      expect(
        () => DocumentMetadata(
          createdAt: created,
          modifiedAt: created,
          minimumReaderVersion: version,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => DocumentMetadata(
        createdAt: created,
        modifiedAt: created,
        createdWithVersion: ' ',
      ),
      throwsArgumentError,
    );
    expect(
      () => DocumentMetadata(
        createdAt: created,
        modifiedAt: created,
        modifiedWithVersion: '',
      ),
      throwsArgumentError,
    );
  });

  test(
    'legacy defaults remain unbound and do not fabricate resource metadata',
    () {
      final board = BoardDocument(
        id: 'board',
        revision: 0,
        elements: [_image(), _text(), _note()],
      );
      expect(board.workspaceId, isNull);
      expect(board.title, '');
      expect(board.canvasSettings.grid.visible, isFalse);
      expect(board.assets, isNull);
      expect(board.fontReferences, isNull);
      expect(board.metadata, isNull);
    },
  );

  test(
    'document snapshots settings, local identity and declared resources',
    () {
      final assets = [
        DocumentAssetReference(
          id: 'image',
          mimeType: 'image/png',
          pixelWidth: 100,
          pixelHeight: 60,
        ),
        DocumentAssetReference(id: 'font-file', mimeType: 'font/ttf'),
      ];
      final fonts = [
        DocumentFontReference(
          id: 'font',
          family: 'Family',
          assetId: 'font-file',
        ),
      ];
      final settings = CanvasSettings(grid: GridSettings(visible: true));
      final metadata = DocumentMetadata(
        createdAt: DateTime.utc(2026, 10, 15),
        modifiedAt: DateTime.utc(2026, 10, 18),
      );
      final board = BoardDocument(
        id: 'portable-identity',
        workspaceId: 'local-copy-identity',
        title: 'رسم\nBoard',
        revision: 0,
        elements: [_image(), _text(), _note()],
        canvasSettings: settings,
        assets: assets,
        fontReferences: fonts,
        metadata: metadata,
      );
      assets.clear();
      fonts.clear();
      expect(board.id, 'portable-identity');
      expect(board.workspaceId, 'local-copy-identity');
      expect(board.title, 'رسم\nBoard');
      expect(board.canvasSettings, same(settings));
      expect(board.metadata, same(metadata));
      expect(board.assets, hasLength(2));
      expect(board.fontReferences, hasLength(1));
      expect(() => board.assets!.clear(), throwsUnsupportedError);
      expect(() => board.fontReferences!.clear(), throwsUnsupportedError);
    },
  );

  test('explicit manifests reject missing and incorrectly typed references', () {
    expect(
      () =>
          BoardDocument(id: 'b', revision: 0, elements: [_image()], assets: []),
      throwsArgumentError,
    );
    expect(
      () => BoardDocument(
        id: 'b',
        revision: 0,
        elements: [_image()],
        assets: [DocumentAssetReference(id: 'image', mimeType: 'font/ttf')],
      ),
      throwsArgumentError,
    );
    for (final content in [_text(), _note()]) {
      expect(
        () => BoardDocument(
          id: 'b',
          revision: 0,
          elements: [content],
          fontReferences: [],
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => BoardDocument(
        id: 'b',
        revision: 0,
        elements: [],
        assets: [],
        fontReferences: [
          DocumentFontReference(id: 'f', family: 'Family', assetId: 'missing'),
        ],
      ),
      throwsArgumentError,
    );
    // A font reference may still be unresolved when no asset manifest is supplied.
    expect(
      BoardDocument(
        id: 'b',
        revision: 0,
        elements: [],
        fontReferences: [
          DocumentFontReference(
            id: 'f',
            family: 'Family',
            assetId: 'unresolved',
          ),
        ],
      ).assets,
      isNull,
    );
  });

  test(
    'manifest identities are unique and unused declared resources are valid',
    () {
      final asset = DocumentAssetReference(id: 'asset', mimeType: 'font/ttf');
      final font = DocumentFontReference(id: 'font', family: 'Family');
      expect(
        () => BoardDocument(
          id: 'b',
          revision: 0,
          elements: [],
          assets: [asset, asset],
        ),
        throwsArgumentError,
      );
      expect(
        () => BoardDocument(
          id: 'b',
          revision: 0,
          elements: [],
          fontReferences: [font, font],
        ),
        throwsArgumentError,
      );
      final board = BoardDocument(
        id: 'b',
        revision: 0,
        elements: [],
        assets: [asset],
        fontReferences: [font],
      );
      expect(board.assets, [asset]);
      expect(board.fontReferences, [font]);
      expect(
        () =>
            BoardDocument(id: 'b', workspaceId: ' ', revision: 0, elements: []),
        throwsArgumentError,
      );
      expect(
        () => BoardDocument(
          id: 'b',
          revision: 0,
          elements: [],
          metadata: DocumentMetadata(
            createdAt: DateTime.utc(2026),
            modifiedAt: DateTime.utc(2026),
            minimumReaderVersion: BoardDocument.currentVersion + 1,
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}

DocumentElement _image() => DocumentElement(
  id: ElementId('image-element'),
  content: ImageElementContent(
    assetId: 'image',
    bounds: Bounds2(0, 0, 100, 60),
  ),
);

ElementTextStyle _textStyle() =>
    ElementTextStyle(fontId: 'font', fontSize: 16, color: 0xff112233);

DocumentElement _text() => DocumentElement(
  id: ElementId('text-element'),
  content: TextElementContent(
    text: 'Text',
    bounds: Bounds2(0, 0, 100, 60),
    style: _textStyle(),
  ),
);

DocumentElement _note() => DocumentElement(
  id: ElementId('note-element'),
  content: StickyNoteElementContent(
    text: 'Note',
    bounds: Bounds2(0, 0, 100, 60),
    style: _textStyle(),
    backgroundColor: 0xffffff00,
  ),
);
