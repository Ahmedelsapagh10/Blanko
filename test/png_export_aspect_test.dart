import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_codec.dart';
import 'package:whiteboard/src/document/document_settings.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/editor/png_export.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

import 'png_export_test.dart' as helper;
import 'support/image_test_bytes.dart';
import 'support/test_board_store.dart';

/// Controlled artwork shared with manual export verification. Image: 64 x 32.
BoardDocument pngAspectFixture() {
  final style = ElementTextStyle(
    fontId: 'editor-sans-v1',
    fontSize: 24,
    color: 0xff172038,
  );
  return BoardDocument(
    id: 'png-aspect-proof',
    title: 'PNG aspect proof',
    revision: 0,
    assets: [
      DocumentAssetReference(
        id: 'aspect-image',
        mimeType: 'image/png',
        pixelWidth: 64,
        pixelHeight: 32,
        byteLength: imageTestPng().length,
      ),
    ],
    fontReferences: [
      DocumentFontReference(id: 'editor-sans-v1', family: 'Roboto'),
    ],
    elements: [
      helper.element(
        'aspect-frame',
        ExportFrameElementContent(
          bounds: Bounds2(0, 0, 600, 400),
          label: 'Aspect proof',
        ),
      ),
      helper.element(
        'circle',
        ShapeElementContent(
          kind: ShapeKind.ellipse,
          bounds: Bounds2(40, 80, 160, 200),
          fillColor: 0xff2266dd,
        ),
      ),
      helper.element(
        'square',
        helper.rectangle(Bounds2(190, 100, 270, 180), 0xff00aa66),
      ),
      helper.element(
        'text',
        TextElementContent(
          text: 'مرحبا Blanko — PNG',
          bounds: Bounds2(30, 20, 560, 65),
          style: style,
        ),
      ),
      helper.element(
        'sticky',
        StickyNoteElementContent(
          text: 'ملاحظة\nKeep proportions',
          bounds: Bounds2(330, 85, 565, 190),
          style: style,
          backgroundColor: 0xffffe070,
        ),
      ),
      helper.element(
        'stroke',
        StrokeElementContent(
          points: [
            Point2(35, 310),
            Point2(110, 275),
            Point2(180, 330),
            Point2(240, 290),
          ],
          style: StrokeStyle(color: 0xff8822aa, width: 9),
        ),
      ),
      helper.element(
        'image',
        ImageElementContent(
          assetId: 'aspect-image',
          bounds: Bounds2(0, 0, 128, 64),
        ),
        transform:
            Transform2.translation(355, 250) * Transform2.rotation(math.pi / 6),
      ),
      helper.element(
        'outside-art',
        helper.rectangle(Bounds2(580, 220, 680, 270), 0xffff3300),
      ),
    ],
  );
}

BoardDocument _document(List<DocumentElement> elements) => BoardDocument(
  id: 'aspect-regression',
  revision: 0,
  elements: elements,
  assets: [],
  fontReferences: [],
);

DocumentElement _circle(Bounds2 bounds, {Transform2? transform}) =>
    helper.element(
      'circle',
      ShapeElementContent(
        kind: ShapeKind.ellipse,
        bounds: bounds,
        fillColor: 0xff0000ff,
      ),
      transform: transform ?? Transform2.identity,
    );

Future<({int width, int height, Uint8List pixels})> _render(
  BoardDocument document, {
  Bounds2? region,
  int width = 200,
  int height = 100,
  int? backgroundColor,
  String? frameId,
  TestBoardStore? store,
}) async => helper.pixels(
  await renderBoardPng(
    document: document,
    store: store,
    bounds: region ?? Bounds2(0, 0, 100, 100),
    width: width,
    height: height,
    backgroundColor: backgroundColor,
    frameId: frameId == null ? null : ElementId(frameId),
  ),
);

({int width, int height, int left, int top}) _extent(
  ({int width, int height, Uint8List pixels}) image, {
  bool Function(int r, int g, int b)? color,
}) {
  var left = image.width, top = image.height, right = -1, bottom = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final offset = (y * image.width + x) * 4;
      if (image.pixels[offset + 3] < 250 ||
          (color != null &&
              !color(
                image.pixels[offset],
                image.pixels[offset + 1],
                image.pixels[offset + 2],
              ))) {
        continue;
      }
      left = math.min(left, x);
      top = math.min(top, y);
      right = math.max(right, x);
      bottom = math.max(bottom, y);
    }
  }
  return (
    width: right - left + 1,
    height: bottom - top + 1,
    left: left,
    top: top,
  );
}

bool _blue(int r, int g, int b) => r < 10 && g < 10 && b > 245;

void main() {
  test(
    'wide and tall output fit centers a circle without changing proportions',
    () async {
      final document = _document([_circle(Bounds2(20, 20, 80, 80))]);
      final wide = await _render(document);
      final tall = await _render(document, width: 100, height: 200);
      for (final image in [wide, tall]) {
        final circle = _extent(image, color: _blue);
        expect(circle.width, inInclusiveRange(58, 60));
        expect(circle.height, inInclusiveRange(58, 60));
        expect((circle.width - circle.height).abs(), lessThanOrEqualTo(1));
      }
      expect(_extent(wide, color: _blue).left, inInclusiveRange(70, 71));
      expect(_extent(tall, color: _blue).top, inInclusiveRange(70, 71));
      expect(helper.at(wide.pixels, 200, 25, 50)[3], 0);
      expect(helper.at(tall.pixels, 100, 50, 25)[3], 0);
    },
  );

  test(
    'image original 64x32 proportions survive mismatched output aspect',
    () async {
      final store = TestBoardStore()..assets['image'] = imageTestPng();
      final document = BoardDocument(
        id: 'image-aspect',
        revision: 0,
        elements: [
          helper.element(
            'image',
            ImageElementContent(
              assetId: 'image',
              bounds: Bounds2(10, 10, 74, 42),
            ),
          ),
        ],
      );
      final image = await _render(document, store: store);
      final extent = _extent(image);
      expect(
        (extent.width, extent.height, extent.left, extent.top),
        (64, 32, 60, 10),
      );
      final original = await helper.pixels(imageTestPng());
      for (final x in [4, 32, 60]) {
        expect(
          helper.at(image.pixels, 200, 60 + x, 26),
          helper.at(original.pixels, 64, x, 16),
        );
      }
    },
  );

  test(
    'padding respects transparent or solid background and clips off-region art',
    () async {
      // This element intersects the source, so broad-phase culling alone cannot
      // prevent its oversized bounds from painting into the output padding.
      final document = _document([
        helper.element(
          'oversized',
          helper.rectangle(Bounds2(-100, -100, 200, 200), 0xffff0000),
        ),
      ]);
      for (final background in [null, 0xff00ff00]) {
        final image = await _render(document, backgroundColor: background);
        final padding = background == null ? [0, 0, 0, 0] : [0, 255, 0, 255];
        expect(helper.at(image.pixels, 200, 25, 50), padding);
        expect(helper.at(image.pixels, 200, 175, 50), padding);
        expect(helper.at(image.pixels, 200, 50, 50), [255, 0, 0, 255]);
        expect(helper.at(image.pixels, 200, 149, 50), [255, 0, 0, 255]);
      }
    },
  );

  test(
    'fit honors a translated source region rather than the world origin',
    () async {
      final document = _document([_circle(Bounds2(40, 50, 100, 110))]);
      final image = await _render(document, region: Bounds2(20, 30, 120, 130));
      final extent = _extent(image, color: _blue);
      expect(extent.left, inInclusiveRange(70, 71));
      expect(extent.top, inInclusiveRange(20, 21));
      expect(helper.at(image.pixels, 200, 100, 50), [0, 0, 255, 255]);
    },
  );

  test(
    'rotated frame fit preserves a world circle and centers padding',
    () async {
      final rigid = Transform2.translation(200, 150) * Transform2.rotation(.47);
      final document = _document([
        helper.element(
          'frame',
          ExportFrameElementContent(bounds: Bounds2(0, 0, 100, 100)),
          transform: rigid,
        ),
        _circle(Bounds2(30, 30, 70, 70), transform: rigid),
      ]);
      final image = await _render(document, frameId: 'frame');
      final circle = _extent(image, color: _blue);
      expect(circle.width, inInclusiveRange(38, 40));
      expect(circle.height, inInclusiveRange(38, 40));
      expect(circle.left, inInclusiveRange(80, 81));
      expect(circle.top, inInclusiveRange(30, 31));
      expect(helper.at(image.pixels, 200, 20, 50)[3], 0);
    },
  );

  test(
    'nested nonuniform export frame does not squeeze independent world artwork',
    () async {
      final rigid = Transform2.translation(200, 150) * Transform2.rotation(.47);
      final document = _document([
        helper.element('owner', const GroupElementContent(), transform: rigid),
        helper.element(
          'frame',
          ExportFrameElementContent(bounds: Bounds2(0, 0, 100, 100)),
          parent: 'owner',
          transform: Transform2.scale(2, 1),
        ),
        _circle(Bounds2(80, 30, 120, 70), transform: rigid),
      ]);
      final image = await _render(
        document,
        width: 200,
        height: 200,
        frameId: 'frame',
      );
      final circle = _extent(image, color: _blue);
      expect(circle.width, inInclusiveRange(38, 40));
      expect(circle.height, inInclusiveRange(38, 40));
      expect(circle.left, inInclusiveRange(80, 81));
      expect(circle.top, inInclusiveRange(80, 81));
      expect(helper.at(image.pixels, 200, 100, 25)[3], 0);
    },
  );

  test(
    'sheared export frame keeps world proportions and clips its polygon',
    () async {
      final rigid = Transform2.translation(200, 150) * Transform2.rotation(.47);
      final document = _document([
        helper.element(
          'frame',
          ExportFrameElementContent(bounds: Bounds2(0, 0, 100, 100)),
          transform: rigid * Transform2(a: 2, c: 1),
        ),
        _circle(Bounds2(135, 35, 165, 65), transform: rigid),
        helper.element(
          'neighbor',
          helper.rectangle(Bounds2(20, 70, 40, 90), 0xffff0000),
          transform: rigid,
        ),
      ]);
      final image = await _render(
        document,
        width: 300,
        height: 100,
        frameId: 'frame',
      );
      final circle = _extent(image, color: _blue);
      expect(circle.width, inInclusiveRange(28, 30));
      expect(circle.height, inInclusiveRange(28, 30));
      expect(circle.left, inInclusiveRange(135, 136));
      expect(circle.top, inInclusiveRange(35, 36));
      expect(helper.at(image.pixels, 300, 30, 80)[3], 0);
      expect(helper.at(image.pixels, 300, 150, 50), [0, 0, 255, 255]);
    },
  );

  test(
    'mixed 4K artwork has actual PNG dimensions and leaves document unchanged',
    () async {
      final document = pngAspectFixture();
      final before = DocumentCodec.encode(document);
      final store = TestBoardStore()..assets['aspect-image'] = imageTestPng();
      final png = await renderBoardPng(
        document: document,
        store: store,
        bounds: Bounds2(0, 0, 600, 400),
        frameId: ElementId('aspect-frame'),
        width: 3840,
        height: 2160,
      );
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final header = ByteData.sublistView(png);
      expect((header.getUint32(16), header.getUint32(20)), (3840, 2160));
      final image = await helper.pixels(png);
      expect((image.width, image.height), (3840, 2160));
      final circle = _extent(
        image,
        color: (r, g, b) => r == 34 && g == 102 && b == 221,
      );
      expect((circle.width - circle.height).abs(), lessThanOrEqualTo(1));
      expect(circle.width, inInclusiveRange(645, 648));
      expect(helper.at(image.pixels, 3840, 100, 100)[3], 0);
      expect(DocumentCodec.encode(document), before);
      expect(document.revision, 0);
      expect(store.writes, 0);
    },
  );
}
