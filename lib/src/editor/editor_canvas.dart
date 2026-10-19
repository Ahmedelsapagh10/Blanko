import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../document/element.dart';
import '../document/document.dart';
import '../document/document_settings.dart';
import '../geometry/geometry.dart';
import '../viewport/camera.dart';
import 'board_session.dart';
import 'editor_scene.dart';

enum EditorTool { select, pan, pen, rectangle, ellipse, triangle, line }

/// Flutter interaction state; only completed gestures enter the pure session.
final class EditorCanvasController extends ChangeNotifier {
  EditorCanvasController({BoardSession? session, this.readOnly = false})
    : session =
          session ??
          BoardSession(
            document: BoardDocument(
              id: 'board',
              title: 'Untitled board',
              revision: 0,
              elements: [],
              assets: [],
              fontReferences: [],
              canvasSettings: CanvasSettings(
                grid: GridSettings(
                  visible: true,
                  spacing: 40,
                  color: 0xffe9edf3,
                ),
              ),
            ),
          ) {
    _refreshScene();
  }

  final BoardSession session;
  final bool readOnly;
  bool inputEnabled = true;
  final toolbarChanges = ValueNotifier<int>(0);
  late EditorScene scene;
  final paths = <ElementId, Path>{};
  Camera camera = Camera(translation: Point2(80, 80));
  EditorTool tool = EditorTool.pen;
  ElementId? selectedId;
  int color = 0xff202d46;
  double strokeWidth = 3;
  bool spaceHeld = false;
  String? message;
  Size viewportSize = Size.zero;
  int? _pointer;
  EditorTool? _gestureTool;
  Point2? _start;
  Point2? _lastScreen;
  final _points = <Point2>[];
  Path? previewPath;
  DocumentElement? previewElement;
  Point2 moveDelta = Point2.zero;
  Camera? _trackpadCamera;
  Point2? _trackpadAnchor;
  bool _disposed = false;

  bool get hasGesture => _pointer != null;
  bool get isNavigating => hasGesture || _trackpadCamera != null;
  int get elementCount => session.document.elements.length;

  void _notify({bool toolbar = false}) {
    if (_disposed) return;
    if (toolbar) toolbarChanges.value++;
    notifyListeners();
  }

  void _refreshScene() {
    scene = EditorScene(session.document);
    paths
      ..clear()
      ..addEntries(
        scene.paintOrder.map((e) => MapEntry(e.id, elementPath(e.content))),
      );
    if (!session.document.byId.containsKey(selectedId)) selectedId = null;
  }

  void setTool(EditorTool value) {
    cancelGesture(notify: false);
    tool = value;
    message = null;
    _notify(toolbar: true);
  }

  void setColor(int value) {
    cancelGesture(notify: false);
    color = value;
    _notify(toolbar: true);
  }

  void setWidth(double value) {
    cancelGesture(notify: false);
    strokeWidth = value;
    _notify(toolbar: true);
  }

  Point2 _world(Offset local) {
    final p = camera.viewportToWorld(Point2(local.dx, local.dy));
    return Point2(p.x.clamp(-1e9, 1e9), p.y.clamp(-1e9, 1e9));
  }

  void pointerDown(PointerDownEvent event) {
    if (_disposed ||
        !inputEnabled ||
        _pointer != null ||
        event.buttons & (kPrimaryMouseButton | kMiddleMouseButton) == 0) {
      return;
    }
    _pointer = event.pointer;
    _gestureTool =
        (readOnly && tool != EditorTool.select) ||
            spaceHeld ||
            event.buttons & kMiddleMouseButton != 0
        ? EditorTool.pan
        : tool;
    _start = _world(event.localPosition);
    _lastScreen = Point2(event.localPosition.dx, event.localPosition.dy);
    message = null;
    if (_gestureTool == EditorTool.select) {
      selectedId = scene.hitTest(
        _start!,
        worldTolerance: camera.worldTolerance(6),
      );
      _notify(toolbar: true);
    } else if (_gestureTool == EditorTool.pen) {
      selectedId = null;
      _points.add(Point2.zero);
      previewPath = Path()..moveTo(0, 0);
      _notify(toolbar: true);
    }
  }

  void pointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final screen = Point2(event.localPosition.dx, event.localPosition.dy);
    final world = _world(event.localPosition);
    switch (_gestureTool) {
      case EditorTool.pan:
        camera = _boundedCamera(camera.pan(screen - _lastScreen!));
      case EditorTool.select:
        if (!readOnly && selectedId != null) moveDelta = world - _start!;
      case EditorTool.pen:
        final relative = world - _start!;
        if (relative.distanceTo(_points.last) * camera.zoom >= .75) {
          if (_points.length < 50000) {
            _points.add(relative);
            previewPath!.lineTo(relative.x, relative.y);
          } else if (message == null) {
            message = 'This stroke is full. Release and start another.';
            toolbarChanges.value++;
          }
        }
      case EditorTool.rectangle ||
          EditorTool.ellipse ||
          EditorTool.triangle ||
          EditorTool.line:
        previewElement = _shape(_start!, world);
        previewPath = previewElement == null
            ? null
            : elementPath(previewElement!.content);
      case null:
        return;
    }
    _lastScreen = screen;
    _notify();
  }

  DocumentElement? _shape(Point2 start, Point2 end) {
    final dx = end.x - start.x, dy = end.y - start.y;
    if (_gestureTool == EditorTool.line) {
      if (start.distanceTo(end) * camera.zoom < 2) return null;
      return DocumentElement(
        id: ElementId('preview'),
        transform: Transform2.translation(start.x, start.y),
        content: LineElementContent(
          start: Point2.zero,
          end: Point2(dx, dy),
          style: StrokeStyle(color: color, width: strokeWidth),
        ),
      );
    }
    if (dx.abs() * camera.zoom < 2 || dy.abs() * camera.zoom < 2) return null;
    return DocumentElement(
      id: ElementId('preview'),
      transform: Transform2.translation(
        math.min(start.x, end.x),
        math.min(start.y, end.y),
      ),
      content: ShapeElementContent(
        kind: switch (_gestureTool) {
          EditorTool.ellipse => ShapeKind.ellipse,
          EditorTool.triangle => ShapeKind.triangle,
          _ => ShapeKind.rectangle,
        },
        bounds: Bounds2(0, 0, dx.abs(), dy.abs()),
        stroke: StrokeStyle(color: color, width: strokeWidth),
      ),
    );
  }

  void pointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    try {
      if (_gestureTool == EditorTool.pen) {
        final world = _world(event.localPosition);
        final relative = world - _start!;
        if (_points.length < 50000 && relative != _points.last) {
          _points.add(relative);
        }
        session.insert(
          StrokeElementContent(
            points: _points,
            style: StrokeStyle(color: color, width: strokeWidth),
          ),
          transform: Transform2.translation(_start!.x, _start!.y),
        );
        _refreshScene();
      } else if (!readOnly &&
          _gestureTool == EditorTool.select &&
          selectedId != null) {
        final delta = _world(event.localPosition) - _start!;
        if (delta.distanceTo(Point2.zero) * camera.zoom >= 2) {
          session.translate(selectedId!, delta);
          _refreshScene();
        }
      } else if (_gestureTool != EditorTool.pan &&
          _gestureTool != EditorTool.select) {
        final shape = _shape(_start!, _world(event.localPosition));
        if (shape != null) {
          selectedId = session.insert(
            shape.content,
            transform: shape.transform,
          );
          _refreshScene();
        }
      }
    } on ArgumentError catch (error) {
      message = 'Could not complete the edit: ${error.message}';
    } on StateError catch (error) {
      message = 'Could not complete the edit: ${error.message}';
    } finally {
      cancelGesture(notify: false);
      _notify(toolbar: true);
    }
  }

  void cancelGesture({bool notify = true}) {
    _pointer = null;
    _gestureTool = null;
    _start = null;
    _lastScreen = null;
    _points.clear();
    previewPath = null;
    previewElement = null;
    moveDelta = Point2.zero;
    if (notify) _notify();
  }

  void deleteSelection() {
    if (readOnly || !inputEnabled) return;
    cancelGesture(notify: false);
    if (selectedId != null && session.delete(selectedId!)) _refreshScene();
    _notify(toolbar: true);
  }

  void undo() {
    if (readOnly || !inputEnabled) return;
    cancelGesture(notify: false);
    if (session.undo()) _refreshScene();
    _notify(toolbar: true);
  }

  void redo() {
    if (readOnly || !inputEnabled) return;
    cancelGesture(notify: false);
    if (session.redo()) _refreshScene();
    _notify(toolbar: true);
  }

  Camera _boundedCamera(Camera value) => Camera(
    zoom: value.zoom,
    translation: Point2(
      value.translation.x.clamp(-1e9 * value.zoom, 1e9 * value.zoom),
      value.translation.y.clamp(-1e9 * value.zoom, 1e9 * value.zoom),
    ),
  );

  void zoom(double factor, [Offset? position]) {
    if (hasGesture) return;
    final anchor =
        position ?? Offset(viewportSize.width / 2, viewportSize.height / 2);
    camera = _boundedCamera(
      camera.zoomAt(Point2(anchor.dx, anchor.dy), camera.zoom * factor),
    );
    _notify(toolbar: true);
  }

  void resetCamera() {
    cancelGesture(notify: false);
    camera = Camera(translation: Point2(80, 80));
    _notify(toolbar: true);
  }

  void pointerSignal(PointerSignalEvent event) {
    if (hasGesture) return;
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
        final scroll = resolved as PointerScrollEvent;
        if (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) {
          zoom(
            math.exp(-scroll.scrollDelta.dy.clamp(-200, 200) * .002),
            scroll.localPosition,
          );
        } else {
          camera = _boundedCamera(
            camera.pan(Point2(-scroll.scrollDelta.dx, -scroll.scrollDelta.dy)),
          );
          _notify();
        }
      });
    } else if (event is PointerScaleEvent) {
      zoom(event.scale, event.localPosition);
    }
  }

  void trackpadStart(PointerPanZoomStartEvent event) {
    cancelGesture(notify: false);
    _trackpadCamera = camera;
    _trackpadAnchor = Point2(event.localPosition.dx, event.localPosition.dy);
    _notify();
  }

  void trackpadUpdate(PointerPanZoomUpdateEvent event) {
    if (_trackpadCamera == null) return;
    camera = _boundedCamera(
      _trackpadCamera!
          .zoomAt(_trackpadAnchor!, _trackpadCamera!.zoom * event.scale)
          .pan(Point2(event.localPan.dx, event.localPan.dy)),
    );
    _notify(toolbar: true);
  }

  void trackpadEnd(PointerPanZoomEndEvent event) {
    _trackpadCamera = null;
    _trackpadAnchor = null;
    _notify(toolbar: true);
  }

  void focusLost() {
    spaceHeld = false;
    _trackpadCamera = null;
    cancelGesture();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelGesture(notify: false);
    _trackpadCamera = null;
    toolbarChanges.dispose();
    paths.clear();
    _points.clear();
    super.dispose();
  }
}

Path elementPath(ElementContent content) {
  final path = Path();
  switch (content) {
    case ShapeElementContent(:final kind, :final bounds):
      final rect = Rect.fromLTRB(
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.bottom,
      );
      switch (kind) {
        case ShapeKind.rectangle:
          path.addRect(rect);
        case ShapeKind.ellipse:
          path.addOval(rect);
        case ShapeKind.triangle:
          path
            ..moveTo(bounds.center.x, bounds.top)
            ..lineTo(bounds.right, bounds.bottom)
            ..lineTo(bounds.left, bounds.bottom)
            ..close();
      }
    case StrokeElementContent(:final points):
      path.moveTo(points.first.x, points.first.y);
      for (final point in points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
    case LineElementContent(:final start, :final end):
      path
        ..moveTo(start.x, start.y)
        ..lineTo(end.x, end.y);
    default:
      throw ArgumentError('This editor slice supports pen, shapes and lines.');
  }
  return path;
}

class EditorCanvas extends StatelessWidget {
  const EditorCanvas({
    super.key,
    required this.controller,
    required this.focusNode,
  });
  final EditorCanvasController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      controller.viewportSize = constraints.biggest;
      return ListenableBuilder(
        listenable: controller.toolbarChanges,
        builder: (context, child) => MouseRegion(
          cursor: controller.tool == EditorTool.pan
              ? SystemMouseCursors.grab
              : controller.tool == EditorTool.select
              ? SystemMouseCursors.basic
              : SystemMouseCursors.precise,
          child: child,
        ),
        child: Listener(
          onPointerDown: (event) {
            focusNode.requestFocus();
            controller.pointerDown(event);
          },
          onPointerMove: controller.pointerMove,
          onPointerUp: controller.pointerUp,
          onPointerCancel: (_) => controller.cancelGesture(),
          onPointerSignal: controller.pointerSignal,
          onPointerPanZoomStart: controller.trackpadStart,
          onPointerPanZoomUpdate: controller.trackpadUpdate,
          onPointerPanZoomEnd: controller.trackpadEnd,
          child: RepaintBoundary(
            child: CustomPaint(
              key: const ValueKey('board-canvas'),
              painter: _EditorPainter(controller),
              size: constraints.biggest,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    },
  );
}

class _EditorPainter extends CustomPainter {
  _EditorPainter(this.controller) : super(repaint: controller);
  final EditorCanvasController controller;
  final _matrix = Float64List(16)
    ..[10] = 1
    ..[15] = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final c = controller;
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(
      Color(c.session.document.canvasSettings.backgroundColor),
      BlendMode.src,
    );
    final view = c.camera.worldViewport(size.width, size.height);
    final origin = Point2(view.left, view.top);
    final grid = c.session.document.canvasSettings.grid;
    if (grid.visible) _grid(canvas, size, c.camera, grid);
    canvas.save();
    canvas.scale(c.camera.zoom);
    for (final element in c.scene.visible(view.inflate(6 / c.camera.zoom))) {
      _element(
        canvas,
        element,
        c.scene.worldTransformOf(element.id),
        c.paths[element.id]!,
        origin,
        delta: element.id == c.selectedId ? c.moveDelta : Point2.zero,
      );
    }
    if (c._gestureTool == EditorTool.pen && c._start != null) {
      canvas.save();
      canvas.translate(c._start!.x - origin.x, c._start!.y - origin.y);
      final paint = Paint()
        ..color = Color(c.color)
        ..style = PaintingStyle.stroke
        ..strokeWidth = c.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (c._points.length == 1) {
        canvas.drawCircle(
          Offset.zero,
          c.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(c.previewPath!, paint);
      }
      canvas.restore();
    } else if (c.previewElement case final element?) {
      _element(canvas, element, element.transform, c.previewPath!, origin);
    }
    final selected = c.selectedId;
    if (selected != null) {
      final bounds = c.scene.boundsOf(selected).inflate(4 / c.camera.zoom);
      canvas.drawRect(
        Rect.fromLTRB(
          bounds.left - origin.x + c.moveDelta.x,
          bounds.top - origin.y + c.moveDelta.y,
          bounds.right - origin.x + c.moveDelta.x,
          bounds.bottom - origin.y + c.moveDelta.y,
        ),
        Paint()
          ..color = const Color(0xff2563eb)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / c.camera.zoom,
      );
    }
    canvas.restore();
  }

  void _element(
    Canvas canvas,
    DocumentElement element,
    Transform2 transform,
    Path path,
    Point2 origin, {
    Point2 delta = Point2.zero,
  }) {
    _matrix[0] = transform.a;
    _matrix[1] = transform.b;
    _matrix[4] = transform.c;
    _matrix[5] = transform.d;
    _matrix[12] = transform.tx - origin.x + delta.x;
    _matrix[13] = transform.ty - origin.y + delta.y;
    canvas.save();
    canvas.transform(_matrix);
    final content = element.content;
    final StrokeStyle? style = switch (content) {
      ShapeElementContent(:final stroke) => stroke,
      StrokeElementContent(:final style) => style,
      LineElementContent(:final style) => style,
      _ => null,
    };
    if (content is ShapeElementContent && content.fillColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(
            content.fillColor!,
          ).withValues(alpha: Color(content.fillColor!).a * element.opacity),
      );
    }
    if (style != null) {
      final color = Color(style.color);
      final alpha =
          element.opacity *
          (content is StrokeElementContent &&
                  content.kind == StrokeKind.highlighter
              ? .28
              : 1);
      final paint = Paint()
        ..color = color.withValues(alpha: color.a * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (content is StrokeElementContent && content.points.length == 1) {
        final point = content.points.single;
        canvas.drawCircle(
          Offset(point.x, point.y),
          style.width / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
  }

  void _grid(Canvas canvas, Size size, Camera camera, GridSettings grid) {
    var spacing = grid.spacing;
    while (spacing * camera.zoom < 18) {
      spacing *= 2;
    }
    final world = camera.worldViewport(size.width, size.height);
    final paint = Paint()
      ..color = Color(grid.color)
      ..strokeWidth = 1;
    for (
      var x = (world.left / spacing).ceil() * spacing;
      x <= world.right;
      x += spacing
    ) {
      final sx = (x - world.left) * camera.zoom;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), paint);
    }
    for (
      var y = (world.top / spacing).ceil() * spacing;
      y <= world.bottom;
      y += spacing
    ) {
      final sy = (y - world.top) * camera.zoom;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), paint);
    }
  }

  @override
  bool shouldRepaint(_EditorPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
