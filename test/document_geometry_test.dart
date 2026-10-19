import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/document/document.dart';
import 'package:whiteboard/src/document/document_geometry.dart';
import 'package:whiteboard/src/document/element.dart';
import 'package:whiteboard/src/geometry/geometry.dart';

DocumentElement node(
  String id, {
  String? parent,
  Transform2 transform = Transform2.identity,
  ElementContent? content,
}) => DocumentElement(
  id: ElementId(id),
  parentId: parent == null ? null : ElementId(parent),
  transform: transform,
  content: content ?? const GroupElementContent(),
);

BoardDocument document(Iterable<DocumentElement> elements) =>
    BoardDocument(id: 'board', revision: 0, elements: elements);

void expectPoint(Point2 actual, Point2 expected, {double tolerance = 1e-8}) {
  expect(actual.x, closeTo(expected.x, tolerance));
  expect(actual.y, closeTo(expected.y, tolerance));
}

void main() {
  test(
    'nested rotation, nonuniform scale, reflection and shear retain all coefficients',
    () {
      final board = document([
        node(
          'root',
          transform: Transform2(a: 0, b: 2, c: -3, d: 0, tx: 100, ty: -50),
        ),
        node(
          'parent',
          parent: 'root',
          transform: Transform2(a: -1, c: 0.5, tx: 10, ty: 20),
        ),
        node(
          'leaf',
          parent: 'parent',
          transform: Transform2.translation(4, -2),
          content: ShapeElementContent(
            kind: ShapeKind.rectangle,
            bounds: Bounds2(0, 0, 10, 10),
            fillColor: 0xff336699,
          ),
        ),
      ]);
      final geometry = DocumentGeometry(board);
      final id = ElementId('leaf');
      // (2, 3) -> (6, 1) -> (4.5, 21) -> (37, -41).
      expectPoint(geometry.localToWorld(id, Point2(2, 3)), Point2(37, -41));
      expectPoint(geometry.worldToLocal(id, Point2(37, -41)), Point2(2, 3));
      expectPoint(
        geometry.worldTransformOf(id).apply(Point2(2, 3)),
        Point2(37, -41),
      );
      expect(board.byId[id]!.transform, Transform2.translation(4, -2));
    },
  );

  test(
    'world lookup follows each owner independently of source or sibling order',
    () {
      final board = document([
        node('b-child', parent: 'b', transform: Transform2.translation(2, 3)),
        node('a-child', parent: 'a', transform: Transform2.translation(7, -9)),
        node('b', transform: Transform2.translation(-100, 200)),
        node('a', transform: Transform2.translation(1000, -2000)),
        node(
          'a-sibling',
          parent: 'a',
          transform: Transform2.translation(-4, 6),
        ),
      ]);
      final geometry = DocumentGeometry(board);
      expectPoint(
        geometry.localToWorld(ElementId('b-child'), Point2.zero),
        Point2(-98, 203),
      );
      expectPoint(
        geometry.localToWorld(ElementId('a-child'), Point2.zero),
        Point2(1007, -2009),
      );
      expectPoint(
        geometry.localToWorld(ElementId('a-sibling'), Point2.zero),
        Point2(996, -1994),
      );
      expect(board.elements.map((element) => element.id.value), [
        'b-child',
        'a-child',
        'b',
        'a',
        'a-sibling',
      ]);
      expect(board.preorder.map((element) => element.id.value), [
        'b',
        'b-child',
        'a',
        'a-child',
        'a-sibling',
      ]);
    },
  );

  test(
    'local and world round trips near plus or minus one billion have a declared tolerance',
    () {
      for (final origin in [-1e9, 0.0, 1e9]) {
        final root =
            Transform2.translation(origin, -origin) *
            Transform2.rotation(0.37) *
            Transform2.scale(-2, 0.75);
        final child = Transform2.translation(24.5, -17.25) * Transform2(c: 0.3);
        final geometry = DocumentGeometry(
          document([
            node('root', transform: root),
            node('child', parent: 'root', transform: child),
          ]),
        );
        for (final local in [
          Point2(13.125, -42.875),
          Point2(origin + 13.125, origin - 42.875),
        ]) {
          final world = geometry.localToWorld(ElementId('child'), local);
          expectPoint(world, root.apply(child.apply(local)), tolerance: 1e-5);
          expectPoint(
            geometry.worldToLocal(ElementId('child'), world),
            local,
            tolerance: 1e-5,
          );
        }
      }
    },
  );

  test(
    'seeded nested affine routes agree with sequential local point mapping',
    () {
      final random = math.Random(204);
      for (var iteration = 0; iteration < 200; iteration++) {
        final transforms = <Transform2>[
          for (var depth = 0; depth < 4; depth++)
            Transform2.translation(
                  random.nextDouble() * 100 - 50,
                  random.nextDouble() * 100 - 50,
                ) *
                Transform2.rotation(random.nextDouble() * math.pi * 2) *
                Transform2.scale(
                  depth.isEven ? -1.5 : 0.75,
                  0.5 + random.nextDouble(),
                ) *
                Transform2(c: random.nextDouble() * 0.5 - 0.25),
        ];
        final geometry = DocumentGeometry(
          document([
            for (var depth = transforms.length - 1; depth >= 0; depth--)
              node(
                'g$depth',
                parent: depth == 0 ? null : 'g${depth - 1}',
                transform: transforms[depth],
              ),
          ]),
        );
        final local = Point2(
          random.nextDouble() * 30,
          random.nextDouble() * 30,
        );
        var expected = local;
        for (final transform in transforms.reversed) {
          expected = transform.apply(expected);
        }
        final world = geometry.localToWorld(ElementId('g3'), local);
        expectPoint(world, expected);
        expectPoint(geometry.worldToLocal(ElementId('g3'), world), local);
      }
    },
  );

  test('missing element lookups fail with an actionable ID', () {
    for (final board in [
      document([]),
      document([node('existing')]),
    ]) {
      final geometry = DocumentGeometry(board);
      final missing = ElementId('missing');
      for (final lookup in <Object Function()>[
        () => geometry.worldTransformOf(missing),
        () => geometry.localToWorld(missing, Point2.zero),
        () => geometry.worldToLocal(missing, Point2.zero),
      ]) {
        expect(
          lookup,
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.invalidValue,
              'id',
              missing,
            ),
          ),
        );
      }
    }
  });

  test(
    'finite local transforms cannot publish an overflowing world composition',
    () {
      for (final transforms in <(Transform2, Transform2)>[
        (Transform2.translation(1e308, 0), Transform2.translation(1e308, 0)),
        (Transform2.scale(1e100, 1e100), Transform2.scale(1e100, 1e100)),
        (Transform2.scale(1e-100, 1e-100), Transform2.scale(1e-100, 1e-100)),
      ]) {
        final board = document([
          node('root', transform: transforms.$1),
          node('overflow', parent: 'root', transform: transforms.$2),
        ]);
        expect(
          () => DocumentGeometry(board),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains('element overflow'),
            ),
          ),
        );
        expect(board.elements, hasLength(2));
      }
    },
  );

  test('point mapping overflow reports both direction and owning element', () {
    final geometry = DocumentGeometry(
      document([
        node('scaled', transform: Transform2.scale(2, 1)),
        node('contracted', transform: Transform2.scale(0.5, 1)),
      ]),
    );
    expect(
      () => geometry.localToWorld(ElementId('scaled'), Point2(1e308, 0)),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message.toString(),
          'message',
          allOf(contains('local point to world'), contains('scaled')),
        ),
      ),
    );
    expect(
      () => geometry.worldToLocal(ElementId('contracted'), Point2(1e308, 0)),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message.toString(),
          'message',
          allOf(contains('world point to local'), contains('contracted')),
        ),
      ),
    );
  });

  test(
    'five thousand nested owners resolve without recursion or ancestor copies',
    () {
      final geometry = DocumentGeometry(
        document([
          for (var i = 4999; i >= 0; i--)
            node(
              'g$i',
              parent: i == 0 ? null : 'g${i - 1}',
              transform: Transform2.translation(1, -0.5),
            ),
        ]),
      );
      expect(geometry.worldTransforms, hasLength(5000));
      expectPoint(
        geometry.localToWorld(ElementId('g4999'), Point2.zero),
        Point2(5000, -2500),
      );
      expectPoint(
        geometry.worldToLocal(ElementId('g4999'), Point2(5002, -2497)),
        Point2(2, 3),
      );
    },
  );

  test('derived state is immutable and belongs to its original snapshot', () {
    final original = document([
      node('same', transform: Transform2.translation(1, 2)),
    ]);
    final geometry = DocumentGeometry(original);
    final replacement = document([
      node('same', transform: Transform2.translation(30, 40)),
    ]);
    final nextGeometry = DocumentGeometry(replacement);
    expect(geometry.document, same(original));
    expect(nextGeometry.document, same(replacement));
    expectPoint(
      geometry.localToWorld(ElementId('same'), Point2.zero),
      Point2(1, 2),
    );
    expectPoint(
      nextGeometry.localToWorld(ElementId('same'), Point2.zero),
      Point2(30, 40),
    );
    expect(() => geometry.worldTransforms.clear(), throwsUnsupportedError);
    expect(
      () => geometry.worldTransforms[ElementId('other')] = Transform2.identity,
      throwsUnsupportedError,
    );
  });
}
