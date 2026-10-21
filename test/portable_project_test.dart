import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/document_geometry.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/persistence/portable_project.dart';
import 'package:whiteboard/src/viewport/camera.dart';

import 'support/image_test_bytes.dart';
import 'support/test_board_store.dart';

BoardSnapshot fixture({String font = 'editor-sans-v1', int? assetLength}) =>
    BoardSnapshot(
      document: BoardDocument(
        id: 'source',
        revision: 7,
        workspaceId: 'local-original',
        title: 'Canvas مرحبا',
        canvasSettings: CanvasSettings(
          backgroundColor: 0xff123456,
          grid: GridSettings(visible: true, spacing: 40),
        ),
        metadata: DocumentMetadata(
          createdAt: DateTime.utc(2026, 1, 1),
          modifiedAt: DateTime.utc(2026, 2, 2),
          createdWithVersion: '0.1',
        ),
        assets: [
          DocumentAssetReference(
            id: 'photo',
            mimeType: 'image/png',
            pixelWidth: 64,
            pixelHeight: 32,
            byteLength: assetLength ?? imageTestPng().length,
          ),
        ],
        fontReferences: [
          DocumentFontReference(
            id: font,
            family: font == 'editor-sans-v1' ? 'Roboto' : 'External Font',
          ),
        ],
        elements: [
          DocumentElement(
            id: ElementId('frame'),
            transform:
                Transform2.translation(120, 90) * Transform2.rotation(.3),
            content: ContainerFrameElementContent(
              bounds: Bounds2(0, 0, 400, 300),
              label: 'Container عربي',
            ),
          ),
          DocumentElement(
            id: ElementId('photo'),
            parentId: ElementId('frame'),
            transform: Transform2.translation(10, 20),
            content: ImageElementContent(
              assetId: 'photo',
              bounds: Bounds2(0, 0, 64, 32),
            ),
          ),
          DocumentElement(
            id: ElementId('text'),
            parentId: ElementId('frame'),
            content: TextElementContent(
              text: 'Hello مرحبا',
              bounds: Bounds2(10, 100, 200, 160),
              style: ElementTextStyle(
                fontId: font,
                fontSize: 24,
                color: 0xff112233,
              ),
              direction: ElementTextDirection.rtl,
            ),
          ),
          DocumentElement(
            id: ElementId('export'),
            content: ExportFrameElementContent(
              bounds: Bounds2(-10, -20, 500, 400),
              label: 'PNG',
              outputWidth: 3840,
              outputHeight: 2160,
            ),
          ),
        ],
      ),
      camera: Camera(translation: Point2(-123.5, 456.75), zoom: 1.25),
      version: 11,
      savedAt: DateTime.utc(2026, 3, 3),
    );

String crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = crc & 1 != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  return ((crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
}

Uint8List alterPayload(
  Uint8List original,
  void Function(Map<String, dynamic>) change,
) {
  final envelope = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
  final payload =
      jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
  change(payload);
  envelope['payload'] = jsonEncode(payload);
  envelope['crc32'] = crc32(utf8.encode(envelope['payload'] as String));
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

class FailingAssetStore extends TestBoardStore {
  @override
  Future<void> writeAsset(String assetId, Uint8List bytes) async =>
      throw StateError('Quota');
}

void main() {
  late TestBoardStore source;
  setUp(() {
    source = TestBoardStore()..assets['photo'] = imageTestPng();
  });

  test(
    'portable image/frame/text round-trip preserves content and remaps independent identity',
    () async {
      final original = fixture();
      final bytes = await exportPortableProject(original, source);
      final project = decodePortableProject(bytes);
      expect(project.assets['photo'], imageTestPng());
      expect(() => project.assets['photo']![0] = 0, throwsUnsupportedError);
      final destination = TestBoardStore()..last = 'existing';
      final imported = await importPortableProject(
        project,
        destination,
        boardId: 'fresh',
        assetPrefix: 'new-assets',
      );
      final document = imported.document;
      expect(document.id, 'fresh');
      expect(document.workspaceId, isNull);
      expect(imported.version, 1);
      expect(destination.last, 'existing');
      expect(document.title, original.document.title);
      expect(
        document.metadata!.createdAt,
        original.document.metadata!.createdAt,
      );
      expect(document.canvasSettings.backgroundColor, 0xff123456);
      expect(imported.camera.translation, original.camera.translation);
      expect(imported.camera.zoom, 1.25);
      expect(
        document.elements.map((e) => e.id),
        original.document.elements.map((e) => e.id),
      );
      expect(
        DocumentGeometry(document).worldTransformOf(ElementId('photo')),
        DocumentGeometry(
          original.document,
        ).worldTransformOf(ElementId('photo')),
      );
      expect(
        (document.byId[ElementId('photo')]!.content as ImageElementContent)
            .assetId,
        'new-assets-0',
      );
      expect(
        (document.byId[ElementId('export')]!.content
                as ExportFrameElementContent)
            .outputWidth,
        3840,
      );
      expect(destination.assets['new-assets-0'], imageTestPng());
      final reopened = await destination.readBoard('fresh');
      expect(
        DocumentCodec.encode(reopened!.document),
        DocumentCodec.encode(document),
      );
      final secondFile = await exportPortableProject(reopened, destination);
      expect(
        decodePortableProject(secondFile).assets['new-assets-0'],
        imageTestPng(),
      );
    },
  );

  test('envelope corruption and newer versions are rejected', () async {
    final bytes = await exportPortableProject(fixture(), source);
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    envelope['payload'] = (envelope['payload'] as String).replaceFirst(
      'Canvas',
      'Broken',
    );
    expect(
      () => decodePortableProject(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      ),
      throwsFormatException,
    );
    envelope['version'] = 2;
    expect(
      () => decodePortableProject(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      ),
      throwsFormatException,
    );
  });

  test(
    'asset checksum, duplicate and declared byte lengths are validated',
    () async {
      final bytes = await exportPortableProject(fixture(), source);
      expect(
        () => decodePortableProject(
          alterPayload(bytes, (p) {
            (p['assets'] as List).first['crc32'] = '00000000';
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => decodePortableProject(
          alterPayload(bytes, (p) {
            (p['assets'] as List).first['byteLength'] = 1;
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => decodePortableProject(
          alterPayload(bytes, (p) {
            (p['assets'] as List).add((p['assets'] as List).first);
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'invalid document hierarchy and viewport are rejected before storage',
    () async {
      final bytes = await exportPortableProject(fixture(), source);
      expect(
        () => decodePortableProject(
          alterPayload(bytes, (p) {
            final d = jsonDecode(p['document'] as String);
            d['elements'][0]['parentId'] = 'photo';
            p['document'] = jsonEncode(d);
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => decodePortableProject(
          alterPayload(bytes, (p) {
            p['camera'] = [0, 0, 1000];
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'missing originals and unsupported fonts fail export explicitly',
    () async {
      source.assets.clear();
      await expectLater(
        exportPortableProject(fixture(), source),
        throwsStateError,
      );
      await expectLater(
        exportPortableProject(fixture(font: 'external'), source),
        throwsFormatException,
      );
    },
  );

  test(
    'project size and individual original limits reject oversized input',
    () async {
      await expectLater(
        exportPortableProject(
          fixture(assetLength: maximumPortableAssetBytes + 1),
          source,
        ),
        throwsFormatException,
      );
      expect(
        () => decodePortableProject(Uint8List(maximumPortableFileBytes + 1)),
        throwsFormatException,
      );
      expect(
        () => decodePortableProject(
            Uint8List.fromList(utf8.encode('${'[' * 17}0${']' * 17}')),
        ),
        throwsFormatException,
      );
      expect(
        () => decodePortableProject(
          Uint8List.fromList(utf8.encode('{"version":1,"version":1}')),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'failed asset or board writes never replace an existing board or last-board setting',
    () async {
      final project = decodePortableProject(
        await exportPortableProject(fixture(), source),
      );
      for (final destination in [FailingAssetStore(), TestBoardStore()]) {
        await destination.writeBoard(fixture(), expectedVersion: null);
        destination.last = 'source';
        final previous = destination.records['source'];
        if (destination is! FailingAssetStore) destination.failWrites = true;
        await expectLater(
          importPortableProject(
            project,
            destination,
            boardId: 'fresh',
            assetPrefix: 'imported',
          ),
          throwsStateError,
        );
        expect(destination.records['source'], previous);
        expect(destination.records.containsKey('fresh'), isFalse);
        expect(destination.last, 'source');
      }
    },
  );

  test(
    'fresh board and asset identities are collision checked before any write',
    () async {
      final project = decodePortableProject(
        await exportPortableProject(fixture(), source),
      );
      final destination = TestBoardStore();
      await destination.writeBoard(fixture(), expectedVersion: null);
      await expectLater(
        importPortableProject(
          project,
          destination,
          boardId: 'source',
          assetPrefix: 'safe',
        ),
        throwsA(isA<StorageConflict>()),
      );
      expect(destination.assets, isEmpty);
      destination.assets['safe-0'] = Uint8List.fromList([7]);
      await expectLater(
        importPortableProject(
          project,
          destination,
          boardId: 'fresh',
          assetPrefix: 'safe',
        ),
        throwsA(isA<StorageConflict>()),
      );
      expect(destination.assets['safe-0'], [7]);
      expect(destination.records.containsKey('fresh'), isFalse);
      await expectLater(
        importPortableProject(
          project,
          destination,
          boardId: 'fresh',
          assetPrefix: '../bad',
        ),
        throwsArgumentError,
      );
    },
  );
}
