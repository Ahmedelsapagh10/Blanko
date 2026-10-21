import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/project_image_validation.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/persistence/board_store.dart';
import 'package:whiteboard/src/persistence/portable_project.dart';
import 'package:whiteboard/src/viewport/camera.dart';

import 'support/image_test_bytes.dart';
import 'support/test_board_store.dart';

Future<PortableProject> project(
  Uint8List bytes, {
  int width = 64,
  int height = 32,
}) async {
  final snapshot = BoardSnapshot(
    document: BoardDocument(
      id: 'original',
      revision: 0,
      assets: [
        DocumentAssetReference(
          id: 'image',
          mimeType: 'image/png',
          pixelWidth: width,
          pixelHeight: height,
          byteLength: bytes.length,
        ),
      ],
      fontReferences: const [],
      elements: [
        DocumentElement(
          id: ElementId('image'),
          content: ImageElementContent(
            assetId: 'image',
            bounds: Bounds2(0, 0, 64, 32),
          ),
        ),
      ],
    ),
    camera: Camera(),
    version: 1,
    savedAt: DateTime.utc(2026),
  );
  final store = TestBoardStore()..assets['image'] = bytes;
  return decodePortableProject(await exportPortableProject(snapshot, store));
}

void main() {
  testWidgets('valid embedded original is decoded and validated', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await validatePortableImages(await project(imageTestPng()));
    });
  });

  testWidgets(
    'CRC-valid but nondecodable originals are rejected before import',
    (tester) async {
      await tester.runAsync(() async {
        final invalid = await project(Uint8List.fromList([1, 2, 3, 4]));
        await expectLater(
          validatePortableImages(invalid),
          throwsFormatException,
        );
      });
    },
  );

  testWidgets('actual original dimensions must match manifest', (tester) async {
    await tester.runAsync(() async {
      final mismatch = await project(imageTestPng(), width: 63);
      await expectLater(
        validatePortableImages(mismatch),
        throwsFormatException,
      );
    });
  });

  testWidgets('unsafe declared pixel counts reject before decoder allocation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final oversized = await project(
        imageTestPng(),
        width: 10000,
        height: 10000,
      );
      await expectLater(
        validatePortableImages(oversized),
        throwsFormatException,
      );
    });
  });
}
