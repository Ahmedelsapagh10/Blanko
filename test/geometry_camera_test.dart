import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/geometry/geometry.dart';
import 'package:whiteboard/src/viewport/camera.dart';

void expectPoint(Point2 actual, Point2 expected, {double tolerance = 1e-7}) {
  expect(actual.x, closeTo(expected.x, tolerance));
  expect(actual.y, closeTo(expected.y, tolerance));
}

void main() {
  test(
    'large-world coordinate round trips stay within a declared double-precision bound',
    () {
      for (final origin in [-1e9, -1e6, 0.0, 1e6, 1e9]) {
        for (final zoom in [Camera.minZoom, 1.0, Camera.maxZoom]) {
          final anchor = Point2(origin + 0.125, origin - 0.375);
          final camera = Camera(translation: anchor * -zoom, zoom: zoom);
          final world = Point2(origin + 10.25, origin - 17.875);
          expectPoint(
            camera.viewportToWorld(camera.worldToViewport(world)),
            world,
            tolerance: 1e-5,
          );
        }
      }
      expect(Transform2.rotation(0.3).maximumScale, closeTo(1, 1e-8));
      expect(Transform2.scale(2, 0.5).maximumScale, closeTo(2, 1e-8));
    },
  );
  test(
    'composition applies child first and maps all rotated bounds corners',
    () {
      final transform =
          Transform2.translation(10, 20) * Transform2.rotation(math.pi / 2);
      expectPoint(transform.apply(Point2(4, 2)), Point2(8, 24));
      final bounds = transform.mapBounds(Bounds2(0, 0, 4, 2));
      expect(bounds.left, closeTo(8, 1e-9));
      expect(bounds.top, closeTo(20, 1e-9));
      expect(bounds.right, closeTo(10, 1e-9));
      expect(bounds.bottom, closeTo(24, 1e-9));
    },
  );

  test(
    '500 generated affine transforms invert and reparent without geometry loss',
    () {
      final random = math.Random(147);
      Transform2 generated() =>
          Transform2.translation(
            random.nextDouble() * 1000 - 500,
            random.nextDouble() * 1000 - 500,
          ) *
          Transform2.rotation(random.nextDouble() * math.pi * 2) *
          Transform2.scale(
            0.1 + random.nextDouble() * 3,
            0.1 + random.nextDouble() * 3,
          ) *
          Transform2(c: random.nextDouble() * 0.8 - 0.4);
      for (var i = 0; i < 500; i++) {
        final world = generated() * generated();
        final newParent = generated();
        final local = world.relativeTo(newParent);
        final point = Point2(
          random.nextDouble() * 200,
          random.nextDouble() * 200,
        );
        expectPoint(world.inverse().apply(world.apply(point)), point);
        expectPoint((newParent * local).apply(point), world.apply(point));
      }
    },
  );

  test(
    'geometry rejects non-finite, singular, and overflowing values at runtime',
    () {
      expect(() => Point2(double.nan, 0), throwsArgumentError);
      expect(() => Bounds2(2, 0, 1, 1), throwsArgumentError);
      expect(() => Bounds2(-1e308, 0, 1e308, 1), throwsArgumentError);
      expect(() => Transform2(a: 0), throwsArgumentError);
      expect(() => Transform2(tx: double.infinity), throwsArgumentError);
      expect(() => Transform2(a: 1e-320), throwsArgumentError);
      expect(() => Bounds2(0, 0, 1, 1).inflate(-1), throwsArgumentError);
    },
  );

  test(
    'camera round-trip, pan, and anchor zoom work at extreme supported zooms',
    () {
      for (final zoom in [Camera.minZoom, 0.5, 1.0, Camera.maxZoom]) {
        final camera = Camera(translation: Point2(-245, 760), zoom: zoom);
        final point = Point2(-3200, 9000);
        expectPoint(
          camera.viewportToWorld(camera.worldToViewport(point)),
          point,
        );
        final anchor = Point2(400, 300);
        final worldAnchor = camera.viewportToWorld(anchor);
        expectPoint(
          camera.zoomAt(anchor, zoom * 2).worldToViewport(worldAnchor),
          anchor,
        );
        final panned = camera.pan(Point2(100, -20));
        expectPoint(
          panned.worldToViewport(point),
          camera.worldToViewport(point) + Point2(100, -20),
        );
        expect(camera.worldTolerance(6) * zoom, closeTo(6, 1e-9));
      }
      final camera = Camera(translation: Point2(40, 20), zoom: 2);
      expect(camera.worldViewport(800, 600), Bounds2(-20, -10, 380, 290));
      expect(camera.zoomAt(Point2.zero, 1000).zoom, Camera.maxZoom);
      expect(camera.zoomAt(Point2.zero, 0.00001).zoom, Camera.minZoom);
      expect(() => Camera(zoom: 0), throwsArgumentError);
      expect(() => camera.zoomAt(Point2.zero, double.nan), throwsArgumentError);
      expect(() => camera.worldViewport(-1, 1), throwsArgumentError);
    },
  );
}
