import '../geometry/geometry.dart';

/// World-to-viewport mapping. Zoom is independent of device pixel ratio.
final class Camera {
  factory Camera({Point2? translation, double zoom = 1}) {
    if (!zoom.isFinite || zoom < minZoom || zoom > maxZoom) {
      throw ArgumentError.value(zoom, 'zoom');
    }
    return Camera._(translation ?? Point2.zero, zoom);
  }

  const Camera._(this.translation, this.zoom);

  static const minZoom = 0.02;
  static const maxZoom = 32.0;
  final Point2 translation;
  final double zoom;

  Point2 worldToViewport(Point2 world) => world * zoom + translation;
  Point2 viewportToWorld(Point2 viewport) =>
      (viewport - translation) * (1 / zoom);

  Camera pan(Point2 viewportDelta) =>
      Camera(translation: translation + viewportDelta, zoom: zoom);

  Camera zoomAt(Point2 viewportAnchor, double requestedZoom) {
    if (!requestedZoom.isFinite || requestedZoom <= 0) {
      throw ArgumentError.value(requestedZoom, 'requestedZoom');
    }
    final nextZoom = requestedZoom.clamp(minZoom, maxZoom);
    final worldAnchor = viewportToWorld(viewportAnchor);
    return Camera(
      translation: viewportAnchor - worldAnchor * nextZoom,
      zoom: nextZoom,
    );
  }

  Bounds2 worldViewport(double width, double height) {
    if (!width.isFinite || !height.isFinite || width < 0 || height < 0) {
      throw ArgumentError(
        'Viewport dimensions must be finite and nonnegative.',
      );
    }
    final start = viewportToWorld(Point2.zero);
    final end = viewportToWorld(Point2(width, height));
    return Bounds2(start.x, start.y, end.x, end.y);
  }

  double worldTolerance(double screenPixels) {
    if (!screenPixels.isFinite || screenPixels < 0) {
      throw ArgumentError.value(screenPixels, 'screenPixels');
    }
    return screenPixels / zoom;
  }
}
