import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../document/element.dart';
import '../document/document.dart';
import '../document/document_settings.dart';
import '../geometry/geometry.dart';
import '../persistence/board_store.dart';
import '../viewport/camera.dart';
import 'board_session.dart';
import 'editor_scene.dart';
import 'stroke_eraser.dart';
import 'editor_text.dart';
import 'image_cache_manager.dart';
import 'image_picker_service.dart';
import 'artwork_painter.dart';

enum EditorTool {
  select,
  pan,
  pen,
  rectangle,
  ellipse,
  triangle,
  line,
  eraser,
  segmentEraser,
  text,
  sticky,
  containerFrame,
  exportFrame,
}

/// Flutter interaction state; only completed gestures enter the pure session.
final class EditorCanvasController extends ChangeNotifier {
  EditorCanvasController({
    BoardSession? session,
    this.readOnly = false,
    this.store,
  }) : session =
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
  final BoardStore? store;
  final imageCache = ImageCacheManager();
  final _requestedAssets = <String>{};
  bool inputEnabled = true;
  final toolbarChanges = ValueNotifier<int>(0);
  late EditorScene scene;
  final paths = <ElementId, Path>{};
  final textLayouts = <ElementId, TextPainter>{};
  void Function(Point2 world, ElementId? id, bool sticky)? onEditText;

  void requestImage(String assetId) {
    if (_disposed ||
        _requestedAssets.contains(assetId) ||
        imageCache.get(assetId) != null ||
        imageCache.errors.containsKey(assetId)) {
      return;
    }
    _requestedAssets.add(assetId);
    imageCache.load(assetId, () async => store?.readAsset(assetId)).then((
      image,
    ) {
      _requestedAssets.remove(assetId);
      if (_disposed ||
          !scene.paintOrder.any(
            (element) =>
                element.content is ImageElementContent &&
                (element.content as ImageElementContent).assetId == assetId,
          )) {
        return;
      }
      if (image == null) {
        message =
            'Image unavailable: ${imageCache.errors[assetId] ?? "could not load original bytes"}. Use Retry images.';
      }
      _notify(toolbar: true);
    });
  }

  void retryImages() {
    imageCache.errors.clear();
    message = null;
    _notify(toolbar: true);
  }

  Future<ElementId?> importImage({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
    Point2? position,
  }) async {
    if (_disposed || readOnly || !inputEnabled) return null;
    if (store == null) {
      message = 'Image import requires local board storage.';
      _notify(toolbar: true);
      return null;
    }
    final center =
        position ??
        camera.viewportToWorld(
          Point2(viewportSize.width / 2, viewportSize.height / 2),
        );
    try {
      final assetId =
          'img-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${math.Random().nextInt(0x7fffffff).toRadixString(36)}';
      var origW = 0, origH = 0;
      final decoded = await imageCache.load(
        assetId,
        () async => bytes,
        onDimensions: (width, height) {
          origW = width;
          origH = height;
        },
      );
      if (_disposed || !inputEnabled) return null;
      if (decoded == null || origW <= 0 || origH <= 0) {
        throw StateError(
          'Unsupported or damaged image: ${imageCache.errors[assetId]}',
        );
      }
      final detectedMime =
          mimeType ??
          (filename.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      await store!.writeAsset(assetId, bytes);
      if (_disposed || !inputEnabled) return null;

      const maxInitialSide = 360.0;
      double width = origW.toDouble();
      double height = origH.toDouble();
      if (width > maxInitialSide || height > maxInitialSide) {
        final scale = maxInitialSide / math.max(width, height);
        width *= scale;
        height *= scale;
      }

      final bounds = Bounds2(
        center.x - width / 2,
        center.y - height / 2,
        center.x + width / 2,
        center.y + height / 2,
      );

      final assetRef = DocumentAssetReference(
        id: assetId,
        mimeType: detectedMime,
        pixelWidth: origW,
        pixelHeight: origH,
        byteLength: bytes.length,
      );

      final content = ImageElementContent(assetId: assetId, bounds: bounds);

      final id = session.insert(content, asset: assetRef);

      selectedId = id;
      _refreshScene();
      requestImage(assetId);
      setTool(EditorTool.select);
      return id;
    } on ArgumentError catch (error) {
      if (_disposed) return null;
      message = 'Could not import image: ${error.message}';
      _notify(toolbar: true);
      return null;
    } on StateError catch (error) {
      if (_disposed) return null;
      message = 'Could not import image: ${error.message}';
      _notify(toolbar: true);
      return null;
    } catch (error) {
      if (_disposed) return null;
      message = 'Could not import image: $error';
      _notify(toolbar: true);
      return null;
    }
  }

  Future<void> pickAndInsertImage() async {
    if (_disposed || readOnly || !inputEnabled) return;
    try {
      final picked = await pickImageFile();
      if (picked != null) {
        await importImage(
          bytes: picked.bytes,
          filename: picked.filename,
          mimeType: picked.mimeType,
        );
      }
    } catch (error) {
      if (_disposed) return;
      message = 'Could not select image file: $error';
      _notify(toolbar: true);
    }
  }

  void rotateSelection([double radians = math.pi / 2]) {
    if (_disposed || readOnly || !inputEnabled || selectedId == null) return;
    if (session.rotate(selectedId!, radians)) {
      _refreshScene();
      _notify(toolbar: true);
    }
  }

  void duplicateSelection() {
    if (_disposed || readOnly || !inputEnabled || selectedId == null) return;
    final dupId = session.duplicate(selectedId!);
    if (dupId != null) {
      selectedId = dupId;
      _refreshScene();
      _notify(toolbar: true);
    }
  }

  void resizeSelection(Bounds2 newBounds) {
    if (_disposed || readOnly || !inputEnabled || selectedId == null) return;
    if (session.resize(selectedId!, newBounds)) {
      _refreshScene();
      _notify(toolbar: true);
    }
  }

  void updateSelectedFrame({
    String? label,
    Bounds2? bounds,
    int? outputWidth,
    int? outputHeight,
  }) {
    if (_disposed || readOnly || !inputEnabled || selectedId == null) return;
    if (session.updateFrame(
      selectedId!,
      label: label,
      bounds: bounds,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
    )) {
      _refreshScene();
      _notify(toolbar: true);
    }
  }

  void reparentSelection(ElementId? parent) {
    if (_disposed || readOnly || !inputEnabled || selectedId == null) return;
    if (session.reparent(selectedId!, parent)) {
      _refreshScene();
      _notify(toolbar: true);
    }
  }

  void setTitle(String title) {
    if (_disposed || readOnly) return;
    session.setTitle(title);
    notifyListeners();
  }

  void saveText(ElementContent content, Point2 world, {ElementId? id}) {
    if (_disposed || readOnly || !inputEnabled) return;
    try {
      if (id == null) {
        selectedId = session.insert(
          content,
          transform: Transform2.translation(world.x, world.y),
          font: DocumentFontReference(id: 'editor-sans-v1', family: 'Roboto'),
        );
      } else {
        session.updateContent(id, content);
        selectedId = id;
      }
      _refreshScene();
      setTool(EditorTool.select);
    } on ArgumentError catch (error) {
      message = 'Could not save text: ${error.message}';
      _notify(toolbar: true);
    } on StateError catch (error) {
      message = 'Could not save text: ${error.message}';
      _notify(toolbar: true);
    }
  }

  void editSelectedText() {
    final element = session.document.byId[selectedId];
    if (element == null ||
        readOnly ||
        !inputEnabled ||
        scene.isLocked(element.id)) {
      return;
    }
    if (element.content is TextElementContent ||
        element.content is StickyNoteElementContent) {
      onEditText?.call(
        scene.worldTransformOf(element.id).apply(Point2.zero),
        element.id,
        element.content is StickyNoteElementContent,
      );
    }
  }

  Camera camera = Camera(translation: Point2(80, 80));
  EditorTool tool = EditorTool.pen;
  ElementId? selectedId;
  int color = 0xff202d46;
  double strokeWidth = 3;
  double eraserSize = 32;
  Point2? eraserPosition;
  final eraseChanges = <ElementId, List<ElementContent>>{};
  bool get isErasing =>
      tool == EditorTool.eraser || tool == EditorTool.segmentEraser;

  void setEraserSize(double value) {
    if (!value.isFinite || value < 4 || value > 120) return;
    cancelGesture(notify: false);
    eraserSize = value;
    _notify(toolbar: true);
  }

  void hover(Offset local) {
    if (!isErasing) return;
    eraserPosition = _world(local);
    _notify();
  }

  void _erase(Point2 from, Point2 to) {
    final radius = camera.worldTolerance(eraserSize / 2);
    if (_gestureTool == EditorTool.segmentEraser) {
      final area = Bounds2.fromPoints([from, to]).inflate(radius);
      for (final element in scene.visible(area)) {
        if (element.content is! StrokeElementContent ||
            scene.isLocked(element.id)) {
          continue;
        }
        final original = element.content as StrokeElementContent;
        final current = eraseChanges[element.id] ?? [original];
        final transform = scene.worldTransformOf(element.id);
        final parts = <ElementContent>[];
        var changed = false;
        for (final content in current.cast<StrokeElementContent>()) {
          final fragments = eraseStrokeSegment(
            points: content.points,
            worldTransform: transform,
            from: from,
            to: to,
            radius: radius + content.style.width * transform.maximumScale / 2,
          );
          if (fragments.length != 1 ||
              !identical(fragments.single, content.points)) {
            changed = true;
          }
          for (final points in fragments) {
            parts.add(
              StrokeElementContent(
                points: points,
                style: content.style,
                kind: content.kind,
              ),
            );
          }
        }
        if (changed) eraseChanges[element.id] = parts;
      }
    } else {
      final steps = math.max(1, (from.distanceTo(to) / (radius / 3)).ceil());
      for (var i = 0; i <= steps; i++) {
        final center = from + (to - from) * (i / steps);
        for (final id in scene.eraserHits(center, radius)) {
          eraseChanges.putIfAbsent(id, () => []);
        }
      }
    }
    eraserPosition = to;
  }

  void clearAll() {
    if (readOnly || !inputEnabled) return;
    cancelGesture(notify: false);
    if (session.clearAll()) _refreshScene();
    _notify(toolbar: true);
  }

  bool spaceHeld = false;
  String? message;
  Size viewportSize = Size.zero;
  final _touches = <int, Point2>{};
  Camera? _touchCamera;
  Point2? _touchAnchor;
  double _touchDistance = 1;
  bool _touchNavigation = false;

  void _startTouchNavigation() {
    final pair = _touches.values.take(2).toList();
    _touchCamera = camera;
    _touchAnchor = (pair[0] + pair[1]) * .5;
    _touchDistance = math.max(1, pair[0].distanceTo(pair[1]));
  }

  void pointerCancel(PointerCancelEvent event) {
    _touches.remove(event.pointer);
    _touchNavigation = _touches.isNotEmpty;
    _touchCamera = null;
    cancelGesture();
  }

  Point2? _handleAnchor;
  Transform2? _handleBase;
  Transform2? _previewWorld;
  Bounds2? _frameBaseBounds;
  Bounds2? _framePreviewBounds;
  Point2? _frameResizeAnchor;
  bool _rotatingHandle = false;

  bool get canTransformSelection {
    final id = selectedId;
    return tool == EditorTool.select &&
        id != null &&
        !readOnly &&
        inputEnabled &&
        !scene.isLocked(id);
  }

  List<Point2>? _frameHandleCorners() {
    final content = session.document.byId[selectedId]?.content;
    final bounds =
        _framePreviewBounds ??
        switch (content) {
          ContainerFrameElementContent(:final bounds) => bounds,
          ExportFrameElementContent(:final bounds) => bounds,
          _ => null,
        };
    if (bounds == null || selectedId == null) return null;
    final world =
        (_previewWorld ?? Transform2.identity) *
        scene.worldTransformOf(selectedId!);
    return [
      Point2(bounds.left, bounds.top),
      Point2(bounds.right, bounds.top),
      Point2(bounds.right, bounds.bottom),
      Point2(bounds.left, bounds.bottom),
    ].map((p) => world.apply(p) + moveDelta).toList();
  }

  bool _beginHandle(Point2 world, bool touch) {
    if (!canTransformSelection) return false;
    final bounds = scene
        .boundsOf(selectedId!)
        .inflate(camera.worldTolerance(4));
    final corners =
        _frameHandleCorners() ??
        [
          Point2(bounds.left, bounds.top),
          Point2(bounds.right, bounds.top),
          Point2(bounds.right, bounds.bottom),
          Point2(bounds.left, bounds.bottom),
        ];
    final tolerance = camera.worldTolerance(touch ? 20 : 9);
    final rotation = Point2(
      bounds.center.x,
      bounds.top - camera.worldTolerance(24),
    );
    final nearestHandle = [
      rotation,
      ...corners,
    ].map(world.distanceTo).reduce(math.min);
    if (world.distanceTo(bounds.center) < nearestHandle) return false;
    for (var i = 0; i < 4; i++) {
      if (world.distanceTo(corners[i]) <= tolerance) {
        _handleAnchor = corners[(i + 2) % 4];
        _handleBase = scene.worldTransformOf(selectedId!);
        final content = session.document.byId[selectedId!]!.content;
        _frameBaseBounds = switch (content) {
          ContainerFrameElementContent(:final bounds) => bounds,
          ExportFrameElementContent(:final bounds) => bounds,
          _ => null,
        };
        if (_frameBaseBounds case final b?) {
          _frameResizeAnchor = [
            Point2(b.right, b.bottom),
            Point2(b.left, b.bottom),
            Point2(b.left, b.top),
            Point2(b.right, b.top),
          ][i];
        }
        return true;
      }
    }
    if (world.distanceTo(rotation) <= tolerance) {
      _handleAnchor = bounds.center;
      _handleBase = scene.worldTransformOf(selectedId!);
      _rotatingHandle = true;
      return true;
    }
    return false;
  }

  void _updateHandle(Point2 world) {
    if (_frameBaseBounds != null && !_rotatingHandle) {
      final local = _handleBase!.inverse().apply(world);
      final anchor = _frameResizeAnchor!;
      if ((local.x - anchor.x).abs() >= 1 && (local.y - anchor.y).abs() >= 1) {
        _framePreviewBounds = Bounds2(
          math.min(local.x, anchor.x),
          math.min(local.y, anchor.y),
          math.max(local.x, anchor.x),
          math.max(local.y, anchor.y),
        );
      }
      return;
    }
    final anchor = _handleAnchor!;
    final start = _start! - anchor;
    final end = world - anchor;
    final scale =
        (end.distanceTo(Point2.zero) /
                math.max(1e-8, start.distanceTo(Point2.zero)))
            .clamp(.05, 100.0)
            .toDouble();
    final delta = _rotatingHandle
        ? Transform2.rotation(
            math.atan2(end.y, end.x) - math.atan2(start.y, start.x),
          )
        : Transform2.scale(scale, scale);
    _previewWorld =
        Transform2.translation(anchor.x, anchor.y) *
        delta *
        Transform2.translation(-anchor.x, -anchor.y);
  }

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
  bool get isNavigating =>
      hasGesture || _trackpadCamera != null || _touchNavigation;
  int get elementCount => session.document.elements.length;

  void _notify({bool toolbar = false}) {
    if (_disposed) return;
    if (toolbar) toolbarChanges.value++;
    notifyListeners();
  }

  void _refreshScene() {
    for (final layout in textLayouts.values) {
      layout.dispose();
    }
    textLayouts.clear();
    scene = EditorScene(session.document);
    imageCache.retainOnly({
      for (final element in session.document.elements)
        if (element.content case ImageElementContent(:final assetId)) assetId,
    });
    for (final element in scene.paintOrder) {
      if (element.content is TextElementContent ||
          element.content is StickyNoteElementContent) {
        textLayouts[element.id] = layoutElementText(element.content);
      }
    }
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
    if (value != EditorTool.select && value != EditorTool.pan) {
      selectedId = null;
    }
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
    if (_disposed || !inputEnabled) return;
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = Point2(
        event.localPosition.dx,
        event.localPosition.dy,
      );
      if (_touches.length >= 2) {
        cancelGesture(notify: false);
        _touchNavigation = true;
        _startTouchNavigation();
        _notify(toolbar: true);
        return;
      }
      if (_touchNavigation) return;
    }
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
    if (_gestureTool == EditorTool.eraser ||
        _gestureTool == EditorTool.segmentEraser) {
      selectedId = null;
      _erase(_start!, _start!);
      _notify(toolbar: true);
    } else if (_gestureTool == EditorTool.select) {
      if (_beginHandle(_start!, event.kind == PointerDeviceKind.touch)) {
        _notify(toolbar: true);
        return;
      }
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
    if (event.kind == PointerDeviceKind.touch &&
        _touches.containsKey(event.pointer)) {
      _touches[event.pointer] = Point2(
        event.localPosition.dx,
        event.localPosition.dy,
      );
      if (_touchNavigation) {
        if (_touches.length >= 2 && _touchCamera != null) {
          final pair = _touches.values.take(2).toList();
          final centroid = (pair[0] + pair[1]) * .5;
          final scale = pair[0].distanceTo(pair[1]) / _touchDistance;
          camera = _boundedCamera(
            _touchCamera!
                .zoomAt(_touchAnchor!, _touchCamera!.zoom * scale)
                .pan(centroid - _touchAnchor!),
          );
          _notify(toolbar: true);
        }
        return;
      }
    }
    if (event.pointer != _pointer) return;
    final screen = Point2(event.localPosition.dx, event.localPosition.dy);
    final world = _world(event.localPosition);
    switch (_gestureTool) {
      case EditorTool.text || EditorTool.sticky:
        break;
      case EditorTool.eraser || EditorTool.segmentEraser:
        _erase(_world(Offset(_lastScreen!.x, _lastScreen!.y)), world);
      case EditorTool.pan:
        camera = _boundedCamera(camera.pan(screen - _lastScreen!));
      case EditorTool.select:
        if (_handleAnchor != null) {
          _updateHandle(world);
        } else if (!readOnly && selectedId != null) {
          moveDelta = world - _start!;
        }
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
          EditorTool.line ||
          EditorTool.containerFrame ||
          EditorTool.exportFrame:
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
    if (_gestureTool == EditorTool.containerFrame ||
        _gestureTool == EditorTool.exportFrame) {
      if (dx.abs() * camera.zoom < 2 || dy.abs() * camera.zoom < 2) return null;
      return DocumentElement(
        id: ElementId('preview'),
        transform: Transform2.translation(
          math.min(start.x, end.x),
          math.min(start.y, end.y),
        ),
        content: _gestureTool == EditorTool.containerFrame
            ? ContainerFrameElementContent(
                bounds: Bounds2(0, 0, dx.abs(), dy.abs()),
                label: 'Frame',
              )
            : ExportFrameElementContent(
                bounds: Bounds2(0, 0, dx.abs(), dy.abs()),
                label: 'Export',
              ),
      );
    }
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
    if (event.kind == PointerDeviceKind.touch) {
      _touches.remove(event.pointer);
      if (_touchNavigation) {
        if (_touches.isEmpty) {
          _touchNavigation = false;
          _touchCamera = null;
        } else if (_touches.length >= 2) {
          _startTouchNavigation();
        }
        _notify(toolbar: true);
        return;
      }
    }
    if (event.pointer != _pointer) return;
    try {
      if (_gestureTool == EditorTool.text ||
          _gestureTool == EditorTool.sticky) {
        final sticky = _gestureTool == EditorTool.sticky;
        final id = scene.hitTest(
          _start!,
          worldTolerance: camera.worldTolerance(4),
        );
        final content = session.document.byId[id]?.content;
        onEditText?.call(
          _start!,
          content is TextElementContent || content is StickyNoteElementContent
              ? id
              : null,
          sticky,
        );
      } else if (_gestureTool == EditorTool.eraser ||
          _gestureTool == EditorTool.segmentEraser) {
        _erase(
          _world(Offset(_lastScreen!.x, _lastScreen!.y)),
          _world(event.localPosition),
        );
        if (session.replaceElements(eraseChanges)) _refreshScene();
      } else if (_gestureTool == EditorTool.pen) {
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
          if (_handleAnchor != null) {
            _updateHandle(_world(event.localPosition));
            if (_framePreviewBounds case final bounds?) {
              session.resize(selectedId!, bounds);
            } else if (_previewWorld != null) {
              session.setWorldTransform(
                selectedId!,
                _previewWorld! * _handleBase!,
              );
            }
          } else {
            session.translate(selectedId!, delta);
          }
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
    eraseChanges.clear();
    _handleAnchor = null;
    _handleBase = null;
    _previewWorld = null;
    _frameBaseBounds = null;
    _framePreviewBounds = null;
    _frameResizeAnchor = null;
    _rotatingHandle = false;
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
    _touches.clear();
    _touchNavigation = false;
    _touchCamera = null;
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
    imageCache.dispose();
    paths.clear();
    for (final layout in textLayouts.values) {
      layout.dispose();
    }
    textLayouts.clear();
    onEditText = null;
    _points.clear();
    super.dispose();
  }
}

Path elementPath(ElementContent content) => artworkPath(content);

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
      if (controller.viewportSize != constraints.biggest) {
        controller.cancelGesture(notify: false);
        controller._touches.clear();
        controller._touchNavigation = false;
        controller._touchCamera = null;
        controller.viewportSize = constraints.biggest;
      }
      return ListenableBuilder(
        listenable: controller.toolbarChanges,
        builder: (context, child) => MouseRegion(
          onHover: (event) => controller.hover(event.localPosition),
          onExit: (_) {
            controller.eraserPosition = null;
            controller._notify();
          },
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
          onPointerCancel: controller.pointerCancel,
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
    var visible = c.scene.visible(view.inflate(6 / c.camera.zoom));
    if (c.selectedId != null &&
        (c.moveDelta != Point2.zero || c._previewWorld != null)) {
      final visibleIds = visible.map((e) => e.id).toSet();
      visible = c.scene.paintOrder
          .where(
            (e) =>
                visibleIds.contains(e.id) ||
                c.scene.belongsTo(e.id, c.selectedId!),
          )
          .toList();
    }
    c.imageCache.updateVisibleAssets(
      {
        for (final element in visible)
          if (element.content case ImageElementContent(:final assetId)) assetId,
      },
      (view.left, view.top, view.right, view.bottom),
    );
    for (final element in visible) {
      final fragments = c.eraseChanges[element.id];
      if (fragments != null) {
        for (final content in fragments) {
          _element(
            canvas,
            element.copyWith(content: content),
            c.scene.worldTransformOf(element.id),
            elementPath(content),
            origin,
          );
        }
        continue;
      }
      final followsSelection =
          c.selectedId != null && c.scene.belongsTo(element.id, c.selectedId!);
      var rendered = element;
      if (element.id == c.selectedId && c._framePreviewBounds != null) {
        final bounds = c._framePreviewBounds!;
        rendered = element.copyWith(
          content: switch (element.content) {
            ContainerFrameElementContent(:final label) =>
              ContainerFrameElementContent(bounds: bounds, label: label),
            ExportFrameElementContent(
              :final label,
              :final outputWidth,
              :final outputHeight,
            ) =>
              ExportFrameElementContent(
                bounds: bounds,
                label: label,
                outputWidth: outputWidth,
                outputHeight: outputHeight,
              ),
            _ => element.content,
          },
        );
      }
      _element(
        canvas,
        rendered,
        followsSelection && c._previewWorld != null
            ? c._previewWorld! * c.scene.worldTransformOf(element.id)
            : c.scene.worldTransformOf(element.id),
        c.paths[element.id]!,
        origin,
        delta: followsSelection ? c.moveDelta : Point2.zero,
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
    if (selected != null &&
        (c.tool == EditorTool.select || c.tool == EditorTool.pan)) {
      final originalBounds = c._framePreviewBounds == null
          ? c.scene.boundsOf(selected)
          : c.scene
                .worldTransformOf(selected)
                .mapBounds(c._framePreviewBounds!);
      final bounds =
          (c._previewWorld?.mapBounds(originalBounds) ?? originalBounds)
              .inflate(4 / c.camera.zoom);
      final l = bounds.left - origin.x + c.moveDelta.x;
      final t = bounds.top - origin.y + c.moveDelta.y;
      final r = bounds.right - origin.x + c.moveDelta.x;
      final b = bounds.bottom - origin.y + c.moveDelta.y;
      final rect = Rect.fromLTRB(l, t, r, b);
      final borderPaint = Paint()
        ..color = const Color(0xFF4464F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / c.camera.zoom;
      canvas.drawRect(rect, borderPaint);

      if (c.canTransformSelection) {
        final handleRadius = 4.0 / c.camera.zoom;
        final handlePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        final handleStroke = Paint()
          ..color = const Color(0xFF4464F6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / c.camera.zoom;

        final frameCorners = c._frameHandleCorners();
        for (final corner
            in frameCorners == null
                ? [Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)]
                : frameCorners.map(
                    (p) => Offset(p.x - origin.x, p.y - origin.y),
                  )) {
          canvas.drawCircle(corner, handleRadius, handlePaint);
          canvas.drawCircle(corner, handleRadius, handleStroke);
        }

        final topCenter = Offset((l + r) / 2, t);
        final rotHandle = Offset((l + r) / 2, t - 24 / c.camera.zoom);
        canvas.drawLine(topCenter, rotHandle, borderPaint);
        canvas.drawCircle(rotHandle, handleRadius, handlePaint);
        canvas.drawCircle(rotHandle, handleRadius, handleStroke);
      }
    }
    canvas.restore();
    if (c.isErasing && c.eraserPosition != null) {
      final p = c.camera.worldToViewport(c.eraserPosition!);
      canvas.drawCircle(
        Offset(p.x, p.y),
        c.eraserSize / 2,
        Paint()
          ..color = const Color(0xff4464f6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
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
    var opacity = element.opacity;
    var parent = controller.session.document.byId[element.parentId];
    while (parent != null) {
      opacity *= parent.opacity;
      parent = controller.session.document.byId[parent.parentId];
    }
    final image = content is ImageElementContent
        ? controller.imageCache.get(content.assetId)
        : null;
    if (content is ImageElementContent && image == null) {
      final rect = artworkRect(content.bounds);
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0xfff1f3f5).withValues(alpha: opacity),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / controller.camera.zoom
          ..color = const Color(0xffced4da).withValues(alpha: opacity),
      );
      if (controller.imageCache.errors.containsKey(content.assetId)) {
        final label = TextPainter(
          text: const TextSpan(
            text: 'Image unavailable',
            style: TextStyle(color: Color(0xffb42318), fontSize: 14),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width);
        canvas.save();
        canvas.clipRect(rect);
        label.paint(canvas, rect.topLeft);
        canvas.restore();
        label.dispose();
      } else {
        controller.requestImage(content.assetId);
      }
    }
    if (content is ContainerFrameElementContent ||
        content is ExportFrameElementContent) {
      final (bounds, name) = switch (content) {
        ContainerFrameElementContent() => (content.bounds, content.label),
        ExportFrameElementContent() => (content.bounds, content.label),
        _ => throw StateError('frame'),
      };
      final isExport = content is ExportFrameElementContent;
      final rect = artworkRect(bounds);
      canvas.drawRect(
        rect,
        Paint()
          ..color =
              (isExport ? const Color(0x064464f6) : const Color(0x04000000))
                  .withValues(alpha: (isExport ? 6 / 255 : 4 / 255) * opacity),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (isExport ? 1.5 : 1) / controller.camera.zoom
          ..color =
              (isExport ? const Color(0xff4464f6) : const Color(0xff94a3b8))
                  .withValues(alpha: opacity),
      );
      final label = TextPainter(
        text: TextSpan(
          text: name.isEmpty ? (isExport ? 'Export frame' : 'Frame') : name,
          style: TextStyle(
            color: isExport ? const Color(0xff4464f6) : const Color(0xff64748b),
            fontSize: math.max(10, 12 / controller.camera.zoom),
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: elementTextDirection(name, ElementTextDirection.auto),
      )..layout();
      label.paint(
        canvas,
        Offset(
          bounds.left,
          bounds.top - label.height - 3 / controller.camera.zoom,
        ),
      );
      label.dispose();
    }
    paintElementArtwork(
      canvas,
      element,
      path: path,
      textLayout: controller.textLayouts[element.id],
      image: image,
      opacity: opacity,
    );
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
