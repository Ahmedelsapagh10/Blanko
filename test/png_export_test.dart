import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/png_export.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'support/image_test_bytes.dart';
import 'support/test_board_store.dart';

DocumentElement element(
  String id,
  ElementContent content, {
  String? parent,
  Transform2 transform = Transform2.identity,
  double opacity = 1,
}) => DocumentElement(
  id: ElementId(id),
  content: content,
  parentId: parent == null ? null : ElementId(parent),
  transform: transform,
  opacity: opacity,
);

ShapeElementContent rectangle(Bounds2 bounds, int color) => ShapeElementContent(
  kind: ShapeKind.rectangle,
  bounds: bounds,
  fillColor: color,
);

Future<({int width, int height, Uint8List pixels})> pixels(
  Uint8List png,
) async {
  final codec = await ui.instantiateImageCodec(png);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final data = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    return (
      width: image.width,
      height: image.height,
      pixels: Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

List<int> at(Uint8List data, int width, int x, int y) =>
    data.sublist((y * width + x) * 4, (y * width + x) * 4 + 4);

void main() {
  final region = Bounds2(0, 0, 100, 100);
  Future<Uint8List> render(
    BoardDocument document, {
    int? backgroundColor,
    int width = 100,
    int height = 100,
    ElementId? frameId,
    TestBoardStore? store,
    bool Function()? isCancelled,
  }) => renderBoardPng(
    document: document,
    store: store,
    bounds: region,
    width: width,
    height: height,
    backgroundColor: backgroundColor,
    frameId: frameId,
    isCancelled: isCancelled,
  );

  test(
    'PNG has requested pixels, order, transparency and no frame guides',
    () async {
      final doc = BoardDocument(
        id: 'png',
        revision: 0,
        elements: [
          element('bottom', rectangle(Bounds2(10, 10, 60, 60), 0xffff0000)),
          element('top', rectangle(Bounds2(30, 30, 70, 70), 0xff0000ff)),
          element(
            'guide',
            ExportFrameElementContent(bounds: region, label: 'Do not export'),
          ),
        ],
      );
      final result = await pixels(await render(doc, width: 200, height: 100));
      expect((result.width, result.height), (200, 100));
      expect(at(result.pixels, result.width, 0, 0), [0, 0, 0, 0]);
      expect(at(result.pixels, result.width, 70, 20), [255, 0, 0, 255]);
      expect(at(result.pixels, result.width, 90, 40), [0, 0, 255, 255]);
      final solid = await pixels(
        await render(doc, backgroundColor: 0xff00ff00),
      );
      expect(at(solid.pixels, solid.width, 0, 0), [0, 255, 0, 255]);
    },
  );

  test(
    'container clips children only in export, retaining inherited opacity',
    () async {
      final doc = BoardDocument(
        id: 'clip',
        revision: 0,
        elements: [
          element(
            'frame',
            ContainerFrameElementContent(bounds: Bounds2(0, 0, 40, 40)),
            transform: Transform2.translation(20, 20),
            opacity: .5,
          ),
          element(
            'child',
            rectangle(Bounds2(-20, -20, 80, 80), 0xffff0000),
            parent: 'frame',
          ),
        ],
      );
      final result = await pixels(await render(doc));
      expect(at(result.pixels, 100, 10, 10), [0, 0, 0, 0]);
      final inside = at(result.pixels, 100, 30, 30);
      expect(inside[0], 255);
      expect(inside[3], inInclusiveRange(127, 128));
      expect(at(result.pixels, 100, 70, 70), [0, 0, 0, 0]);
    },
  );

  test('rotated export frame crops in its local coordinates', () async {
    final transform =
        Transform2.translation(80, 20) *
        Transform2.rotation(1.5707963267948966);
    final doc = BoardDocument(
      id: 'rotated',
      revision: 0,
      elements: [
        element(
          'guide',
          ExportFrameElementContent(bounds: Bounds2(0, 0, 40, 20)),
          transform: transform,
        ),
        element(
          'art',
          rectangle(Bounds2(0, 0, 20, 20), 0xff00ff00),
          transform: transform,
        ),
      ],
    );
    final result = await pixels(
      await render(doc, width: 80, height: 40, frameId: ElementId('guide')),
    );
    expect(at(result.pixels, 80, 10, 20), [0, 255, 0, 255]);
    expect(at(result.pixels, 80, 70, 20), [0, 0, 0, 0]);
  });

  test(
    'original image bytes and mixed Arabic text/sticky compose into PNG',
    () async {
      final store = TestBoardStore()
        ..assets['image'] = imageTestPng().asUnmodifiableView();
      final style = ElementTextStyle(
        fontId: 'font',
        fontSize: 14,
        color: 0xff000000,
      );
      final doc = BoardDocument(
        id: 'mixed',
        revision: 0,
        elements: [
          element(
            'image',
            ImageElementContent(
              assetId: 'image',
              bounds: Bounds2(0, 0, 64, 32),
            ),
          ),
          element(
            'note',
            StickyNoteElementContent(
              text: 'مرحبا Blanko',
              bounds: Bounds2(0, 35, 100, 100),
              style: style,
              backgroundColor: 0xffffff00,
            ),
          ),
        ],
      );
      final result = await pixels(await render(doc, store: store));
      final original = await pixels(imageTestPng());
      for (final x in [4, 32, 60]) {
        expect(at(result.pixels, 100, x, 16), at(original.pixels, 64, x, 16));
      }
      expect(at(result.pixels, 100, 2, 95), [255, 255, 0, 255]);
      var textPixels = 0;
      for (var y = 47; y < 95; y++) {
        for (var x = 12; x < 88; x++) {
          final pixel = at(result.pixels, 100, x, y);
          if (pixel[0] < 200 && pixel[1] < 200 && pixel[3] == 255) textPixels++;
        }
      }
      expect(textPixels, greaterThan(30));
    },
  );

  test(
    'missing/corrupt assets fail instead of exporting placeholders; retry works',
    () async {
      final store = TestBoardStore();
      final doc = BoardDocument(
        id: 'missing',
        revision: 0,
        elements: [
          element(
            'image',
            ImageElementContent(assetId: 'image', bounds: region),
          ),
        ],
      );
      await expectLater(render(doc, store: store), throwsStateError);
      store.assets['image'] = Uint8List.fromList([1, 2, 3]);
      await expectLater(render(doc, store: store), throwsA(anything));
      store.assets['image'] = imageTestPng();
      expect((await pixels(await render(doc, store: store))).width, 100);
    },
  );

  test(
    'limits and cancellation refuse work without mutating the document',
    () async {
      final doc = BoardDocument(id: 'limit', revision: 0, elements: []);
      await expectLater(render(doc, width: 8193), throwsArgumentError);
      await expectLater(
        render(doc, width: 8192, height: 8192),
        throwsArgumentError,
      );
      await expectLater(
        render(doc, isCancelled: () => true),
        throwsA(isA<PngExportCancelled>()),
      );
      expect(doc.revision, 0);
      expect(doc.elements, isEmpty);
    },
  );

  test('4K preset produces a real 3840 by 2160 PNG', () async {
    final doc = BoardDocument(
      id: '4k',
      revision: 0,
      elements: [element('art', rectangle(region, 0xff4464f6))],
    );
    final result = await pixels(await render(doc, width: 3840, height: 2160));
    expect((result.width, result.height), (3840, 2160));
    expect(at(result.pixels, 3840, 1920, 1080), [68, 100, 246, 255]);
  });
}
