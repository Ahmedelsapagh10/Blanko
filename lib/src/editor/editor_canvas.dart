import 'dart:async';
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
import 'stroke_sampling.dart';
import 'editor_text.dart';
import 'image_cache_manager.dart';
import 'image_picker_service.dart';
import 'artwork_painter.dart';
import 'editor_clipboard.dart';
import 'selection_snapping.dart';

enum EditorTool {
  select,
  pan,
  pen,
  highlighter,
  rectangle,
  ellipse,
  triangle,
  line,
  arrow,
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
    EditorClipboard? clipboard,
  }) : clipboard = clipboard ?? EditorClipboard(),
       _ownsClipboard = clipboard == null,
       session =
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
    this.clipboard.addListener(_clipboardChanged);
  }

  final EditorClipboard clipboard;
  final bool _ownsClipboard;
  void _clipboardChanged() => _notify(toolbar: true);
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
    if (!canEditSelection) return;
    final center = selectionBounds!.center;
    _command(
      () => session.transformMany(
        _selectedIds,
        Transform2.translation(center.x, center.y) *
            Transform2.rotation(radians) *
            Transform2.translation(-center.x, -center.y),
      ),
    );
  }

  void duplicateSelection() {
    if (!canEditSelection) return;
    _command(() {
      final ids = session.duplicateMany(_selectedIds);
      _setSelection(ids);
      return ids.isNotEmpty;
    });
  }

  void _command(bool Function() action) {
    if (_disposed) return;
    cancelGesture(notify: false);
    try {
      if (action()) _refreshScene();
    } on ArgumentError catch (error) {
      message = '$error';
    } on StateError catch (error) {
      message = error.message;
    }
    _notify(toolbar: true);
  }

  void groupSelection() {
    if (!canEditSelection) return;
    if (!session.canGroup(_selectedIds)) {
      message = 'Select at least two elements in the same frame or group.';
      _notify(toolbar: true);
      return;
    }
    _command(() {
      final id = session.group(_selectedIds);
      if (id != null) _setSelection([id]);
      return id != null;
    });
  }

  void ungroupSelection() {
    if (!canEditSelection) return;
    _command(() {
      final revision = session.document.revision;
      final ids = session.ungroup(_selectedIds);
      if (session.document.revision != revision) _setSelection(ids);
      return session.document.revision != revision;
    });
  }

  void lockSelection(bool locked) {
    if (readOnly || !inputEnabled || clipboardBusy) return;
    _command(() => session.setLockedMany(_selectedIds, locked));
  }

  void unlockElement(ElementId id) {
    if (readOnly || !inputEnabled || clipboardBusy) return;
    _command(() => session.setLockedMany([id], false));
  }

  void reorderSelection(String action) {
    if (canEditSelection) {
      _command(() => session.reorderMany(_selectedIds, action));
    }
  }

  void layoutSelection(String action) {
    if (!canEditSelection) return;
    if (!selectionSharesParent) {
      message = 'Align elements within the same frame or group.';
      _notify(toolbar: true);
      return;
    }
    if (!canLayoutSelection(action)) return;
    _command(
      () => session.translateMany(
        selectionLayout({
          for (final id in _selectedIds) id: scene.boundsOf(id),
        }, action),
      ),
    );
  }

  void exitGroup() {
    editingGroupId = null;
    _setSelection([]);
    _notify(toolbar: true);
  }

  void toggleSnapping({required bool objects}) {
    if (objects) {
      objectSnapping = !objectSnapping;
    } else {
      gridSnapping = !gridSnapping;
    }
    _notify(toolbar: true);
  }

  void enterGroup() {
    if (session.document.byId[selectedId]?.content is! GroupElementContent) {
      return;
    }
    editingGroupId = selectedId;
    _setSelection([]);
    _notify(toolbar: true);
  }

  Future<void> copySelection({bool cut = false}) async {
    if (_disposed ||
        !inputEnabled ||
        clipboardBusy ||
        !hasSelection ||
        (cut && !canEditSelection)) {
      return;
    }
    final document = session.document;
    final ids = _selectedIds.toList();
    clipboardBusy = true;
    cancelGesture(notify: false);
    _notify(toolbar: true);
    try {
      await clipboard.copy(document, ids, store);
      if (_disposed) return;
      if (cut && inputEnabled && identical(document, session.document)) {
        session.deleteMany(ids);
        _refreshScene();
      }
    } catch (error) {
      if (!_disposed) message = 'Could not copy selection: $error';
    } finally {
      clipboardBusy = false;
      if (!_disposed) _notify(toolbar: true);
    }
  }

  Future<void> pasteSelection() async {
    if (_disposed ||
        readOnly ||
        !inputEnabled ||
        clipboardBusy ||
        !clipboard.hasContent) {
      return;
    }
    final document = session.document;
    clipboardBusy = true;
    cancelGesture(notify: false);
    _notify(toolbar: true);
    try {
      final fragment = await clipboard.preparePaste(
        store,
        isCancelled: () =>
            _disposed ||
            !inputEnabled ||
            !identical(document, session.document),
      );
      if (_disposed ||
          !inputEnabled ||
          !identical(document, session.document)) {
        return;
      }
      final fragmentScene = EditorScene(fragment);
      Bounds2? bounds;
      for (final element in fragment.elements.where(
        (e) => e.parentId == null,
      )) {
        final b = fragmentScene.boundsOf(element.id);
        bounds = bounds == null
            ? b
            : Bounds2(
                math.min(bounds.left, b.left),
                math.min(bounds.top, b.top),
                math.max(bounds.right, b.right),
                math.max(bounds.bottom, b.bottom),
              );
      }
      final center = camera.viewportToWorld(
        Point2(viewportSize.width / 2, viewportSize.height / 2),
      );
      final sourceCenter = bounds?.center ?? Point2.zero;
      final view = camera.worldViewport(
        viewportSize.width,
        viewportSize.height,
      );
      final base = view.contains(sourceCenter) ? sourceCenter : center;
      final step = 24 * (++_pasteCount % 8 + 1) / camera.zoom;
      final ids = session.insertFragment(
        fragment,
        offset: base + Point2(step, step) - sourceCenter,
      );
      _setSelection(ids);
      _refreshScene();
      tool = EditorTool.select;
    } catch (error) {
      if (!_disposed) message = 'Could not paste: $error';
    } finally {
      clipboardBusy = false;
      if (!_disposed) _notify(toolbar: true);
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
  final _selectedIds = <ElementId>{};
  final _selectedTree = <ElementId>{};
  Set<ElementId> get selectedIds => Set.unmodifiable(_selectedIds);
  ElementId? get selectedId =>
      _selectedIds.length == 1 ? _selectedIds.single : null;
  set selectedId(ElementId? id) => _setSelection(id == null ? [] : [id]);
  bool get hasSelection => _selectedIds.isNotEmpty;
  bool multiSelectMode = false;
  ElementId? editingGroupId;
  bool clipboardBusy = false;
  int _pasteCount = 0;
  bool objectSnapping = true;
  bool gridSnapping = false;
  List<SnapGuide> snapGuides = const [];
  Timer? _longPressTimer;
  void Function(Offset global)? onContextMenu;
  Bounds2? marqueeBounds;
  Point2? _marqueeStart;
  Set<ElementId> _marqueeBase = {};
  Set<ElementId> _selectionBeforeGesture = {};
  Point2? _pressScreen;
  bool _togglingSelection = false;
  Bounds2? _gestureSelectionBounds;
  List<Bounds2> _snapCandidates = const [];

  void _setSelection(Iterable<ElementId> ids) {
    final roots = session.selectionRoots(ids);
    _selectedIds
      ..clear()
      ..addAll(roots);
    _selectedTree.clear();
    final pending = [..._selectedIds];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!_selectedTree.add(id)) continue;
      pending.addAll(session.document.childrenOf(id).map((e) => e.id));
    }
  }

  Bounds2? get selectionBounds {
    Bounds2? result;
    for (final id in _selectedIds) {
      final b = scene.boundsOf(id);
      result = result == null
          ? b
          : Bounds2(
              math.min(result.left, b.left),
              math.min(result.top, b.top),
              math.max(result.right, b.right),
              math.max(result.bottom, b.bottom),
            );
    }
    return result;
  }

  bool get canEditSelection =>
      !readOnly &&
      inputEnabled &&
      !clipboardBusy &&
      hasSelection &&
      _selectedIds.every(session.canEdit);

  bool get selectionSharesParent =>
      _selectedIds
          .map((id) => session.document.byId[id]!.parentId)
          .toSet()
          .length ==
      1;

  bool canLayoutSelection(String action) =>
      canEditSelection &&
      selectionSharesParent &&
      _selectedIds.length >= (action.startsWith('distribute') ? 3 : 2);

  ElementId _selectionTarget(ElementId id) {
    var target = id;
    var parent = session.document.byId[id]?.parentId;
    while (parent != null && parent != editingGroupId) {
      if (session.document.byId[parent]!.content is GroupElementContent) {
        target = parent;
      }
      parent = session.document.byId[parent]!.parentId;
    }
    return target;
  }

  void selectAll() {
    cancelGesture(notify: false);
    _setSelection(
      scene.paintOrder
          .map((e) => _selectionTarget(e.id))
          .where(
            (id) =>
                session.canEdit(id) &&
                (editingGroupId == null ||
                    scene.belongsTo(id, editingGroupId!)),
          ),
    );
    _notify(toolbar: true);
  }

  void escapeSelection() {
    if (hasGesture) {
      final previous = _marqueeStart == null
          ? null
          : _selectionBeforeGesture.toList();
      cancelGesture(notify: false);
      if (previous != null) _setSelection(previous);
      _notify(toolbar: true);
      return;
    }
    if (hasSelection) {
      _setSelection([]);
    } else {
      editingGroupId = null;
    }
    _notify(toolbar: true);
  }

  void toggleMultiSelect() {
    cancelGesture(notify: false);
    multiSelectMode = !multiSelectMode;
    _notify(toolbar: true);
  }

  void contextAt(Offset local, Offset global) {
    cancelGesture(notify: false);
    var hit = scene.hitTest(
      _world(local),
      worldTolerance: camera.worldTolerance(6),
      includeLocked: true,
    );
    if (hit != null &&
        editingGroupId != null &&
        !scene.belongsTo(hit, editingGroupId!)) {
      hit = null;
    }
    if (hit != null) {
      var target = _selectionTarget(hit);
      var current = session.document.byId[hit];
      while (current != null) {
        if (current.locked) target = current.id;
        current = session.document.byId[current.parentId];
      }
      if (!_selectedTree.contains(hit)) _setSelection([target]);
    }
    _notify(toolbar: true);
    onContextMenu?.call(global);
  }

  void _prepareSnapping() {
    _gestureSelectionBounds = selectionBounds;
    final parents = _selectedIds
        .map((id) => session.document.byId[id]!.parentId)
        .toSet();
    final ids = scene
        .visible(
          camera
              .worldViewport(viewportSize.width, viewportSize.height)
              .inflate(camera.worldTolerance(64)),
        )
        .map((e) => _selectionTarget(e.id))
        .toSet();
    _snapCandidates = ids
        .where(
          (id) =>
              !_selectedTree.contains(id) &&
              parents.contains(session.document.byId[id]!.parentId),
        )
        .take(128)
        .map(scene.boundsOf)
        .toList();
  }

  void _updateMove(Point2 delta) {
    final result = snapMove(
      movingBounds: _gestureSelectionBounds ?? selectionBounds!,
      delta: delta,
      candidates: objectSnapping ? _snapCandidates : const [],
      tolerance: camera.worldTolerance(6),
      gridSpacing: gridSnapping
          ? session.document.canvasSettings.grid.spacing
          : null,
    );
    moveDelta = result.delta;
    snapGuides = result.guides;
  }

  void _updateMarquee(Point2 point) {
    final start = _marqueeStart!;
    final area = Bounds2(
      math.min(start.x, point.x),
      math.min(start.y, point.y),
      math.max(start.x, point.x),
      math.max(start.y, point.y),
    );
    marqueeBounds = area;
    final ids = scene.visible(area).map((e) => _selectionTarget(e.id)).toSet();
    _setSelection({
      ..._marqueeBase,
      ...ids.where((id) {
        if (!session.canEdit(id) ||
            (editingGroupId != null && !scene.belongsTo(id, editingGroupId!))) {
          return false;
        }
        final content = session.document.byId[id]!.content;
        if (content is ContainerFrameElementContent ||
            content is ExportFrameElementContent) {
          final b = scene.boundsOf(id);
          return area.left <= b.left &&
              area.top <= b.top &&
              area.right >= b.right &&
              area.bottom >= b.bottom;
        }
        return true;
      }),
    });
    _notify(toolbar: true);
  }

  int color = 0xff202d46;
  double strokeWidth = 3;
  int highlighterColor = 0xffffd54f;
  double highlighterWidth = 24;
  double highlighterOpacity = .35;
  double strokeOpacity = 1;
  int? fillColor;
  bool dashed = false;
  ArrowHeadStyle arrowHeads = ArrowHeadStyle.end;
  double get activeStrokeWidth =>
      tool == EditorTool.highlighter ? highlighterWidth : strokeWidth;
  int get activeColor =>
      tool == EditorTool.highlighter ? highlighterColor : color;
  int get activeStrokeColor => tool == EditorTool.highlighter
      ? highlighterColor
      : withOpacity(color, strokeOpacity);
  static int withOpacity(int color, double opacity) =>
      ((opacity.clamp(0, 1) * 255).round() << 24) | (color & 0xffffff);
  static bool isDrawingContent(ElementContent content) =>
      content is ShapeElementContent ||
      content is StrokeElementContent ||
      content is LineElementContent ||
      content is ArrowElementContent;
  ElementContent? get selectedDrawing => scene.paintOrder
      .where((e) => _selectedTree.contains(e.id) && isDrawingContent(e.content))
      .firstOrNull
      ?.content;
  bool get canStyleSelection => canEditSelection && selectedDrawing != null;
  void applyDrawingStyle({
    required int strokeColor,
    required double width,
    required double opacity,
    required int? fill,
    required bool dash,
    required ArrowHeadStyle heads,
    required double markerOpacity,
    bool applyFill = true,
    bool applyDash = true,
    bool applyHeads = true,
    bool applyMarkerOpacity = true,
  }) {
    if (readOnly || !inputEnabled || clipboardBusy || _disposed) return;
    cancelGesture(notify: false);
    if (tool == EditorTool.select) {
      if (!canStyleSelection) return;
      _command(
        () => session.styleMany(
          _selectedIds,
          strokeColor: withOpacity(strokeColor, opacity),
          strokeWidth: width,
          fillColor: applyFill ? fill : null,
          clearFill: applyFill && fill == null,
          dashed: applyDash ? dash : null,
          arrowHeads: applyHeads ? heads : null,
          highlighterOpacity: applyMarkerOpacity ? markerOpacity : null,
        ),
      );
    } else {
      if (tool == EditorTool.highlighter) {
        highlighterColor = strokeColor;
        highlighterWidth = width;
        highlighterOpacity = markerOpacity;
      } else {
        color = strokeColor;
        strokeWidth = width;
        strokeOpacity = opacity;
        fillColor = fill;
        dashed = dash;
        arrowHeads = heads;
      }
      _notify(toolbar: true);
    }
  }

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
                highlighterOpacity: content.highlighterOpacity,
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
    if (readOnly || !inputEnabled || clipboardBusy) return;
    if (session.document.elements.any((e) => e.locked)) {
      message = 'Unlock locked items before clearing the board.';
      _notify(toolbar: true);
      return;
    }
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
    final previous = _marqueeStart == null
        ? null
        : _selectionBeforeGesture.toList();
    cancelGesture(notify: false);
    if (previous != null) _setSelection(previous);
    _notify(toolbar: true);
  }

  Point2? _handleAnchor;
  Transform2? _handleBase;
  Transform2? _previewWorld;
  Bounds2? _frameBaseBounds;
  Bounds2? _framePreviewBounds;
  Point2? _frameResizeAnchor;
  bool _rotatingHandle = false;

  bool get canTransformSelection {
    return tool == EditorTool.select && canEditSelection;
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
    final bounds = selectionBounds!.inflate(camera.worldTolerance(4));
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
        _handleBase = selectedId == null
            ? Transform2.identity
            : scene.worldTransformOf(selectedId!);
        final content = session.document.byId[selectedId]?.content;
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
      _handleBase = selectedId == null
          ? Transform2.identity
          : scene.worldTransformOf(selectedId!);
      _rotatingHandle = true;
      return true;
    }
    return false;
  }

  void _updateHandle(Point2 world) {
    if (_frameBaseBounds != null && !_rotatingHandle) {
      final snap = snapMove(
        movingBounds: Bounds2(world.x, world.y, world.x, world.y),
        delta: Point2.zero,
        candidates: objectSnapping ? _snapCandidates : const [],
        tolerance: camera.worldTolerance(6),
        gridSpacing: gridSnapping
            ? session.document.canvasSettings.grid.spacing
            : null,
      );
      world = world + snap.delta;
      snapGuides = snap.guides;
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
    if (!_rotatingHandle) {
      final snap = snapMove(
        movingBounds: Bounds2(world.x, world.y, world.x, world.y),
        delta: Point2.zero,
        candidates: objectSnapping ? _snapCandidates : const [],
        tolerance: camera.worldTolerance(6),
        gridSpacing: gridSnapping
            ? session.document.canvasSettings.grid.spacing
            : null,
      );
      final start = _start! - anchor;
      final vertical = snap.guides.any((g) => g.vertical);
      final horizontal = snap.guides.any((g) => !g.vertical);
      final xScale = start.x == 0
          ? null
          : (world.x + snap.delta.x - anchor.x) / start.x;
      final yScale = start.y == 0
          ? null
          : (world.y + snap.delta.y - anchor.y) / start.y;
      final scale = vertical
          ? xScale
          : horizontal
          ? yScale
          : gridSnapping && snap.delta != Point2.zero
          ? xScale
          : null;
      if (scale != null && scale >= .05 && scale <= 100) {
        _previewWorld =
            Transform2.translation(anchor.x, anchor.y) *
            Transform2.scale(scale, scale) *
            Transform2.translation(-anchor.x, -anchor.y);
        snapGuides = snap.guides.where((g) => g.vertical == vertical).toList();
        return;
      }
      snapGuides = const [];
    }
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
  StrokeSampler? _sampler;
  StrokeStyle? _gestureStrokeStyle;
  double _gestureHighlighterOpacity = .35;
  Path? _strokeTail;
  void _appendStrokeSamples(Iterable<Point2> points) {
    for (final point in points) {
      if (_points.length >= 50000) {
        if (message == null) {
          message = 'This stroke is full. Release and start another.';
          toolbarChanges.value++;
        }
        break;
      }
      if (_points.isNotEmpty && _points.last == point) continue;
      if (_points.isEmpty) {
        previewPath!.moveTo(point.x, point.y);
      } else {
        previewPath!.lineTo(point.x, point.y);
      }
      _points.add(point);
    }
  }

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
    _setSelection(
      _selectedIds.where(session.document.byId.containsKey).toList(),
    );
    if (!session.document.byId.containsKey(editingGroupId)) {
      editingGroupId = null;
    }
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
    if (tool == EditorTool.highlighter) {
      highlighterColor = value;
    } else {
      color = value;
    }
    _notify(toolbar: true);
  }

  void setWidth(double value) {
    cancelGesture(notify: false);
    if (tool == EditorTool.highlighter) {
      highlighterWidth = value;
    } else {
      strokeWidth = value;
    }
    _notify(toolbar: true);
  }

  Point2 _world(Offset local) {
    final p = camera.viewportToWorld(Point2(local.dx, local.dy));
    return Point2(p.x.clamp(-1e9, 1e9), p.y.clamp(-1e9, 1e9));
  }

  void pointerDown(PointerDownEvent event) {
    if (_disposed || !inputEnabled || clipboardBusy) return;
    if (event.buttons & kSecondaryMouseButton != 0) {
      contextAt(event.localPosition, event.position);
      return;
    }
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
    _selectionBeforeGesture = {..._selectedIds};
    _pressScreen = Point2(event.localPosition.dx, event.localPosition.dy);
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
        _prepareSnapping();
        _notify(toolbar: true);
        return;
      }
      final hit = scene.hitTest(
        _start!,
        worldTolerance: camera.worldTolerance(6),
      );
      final target =
          hit == null ||
              (editingGroupId != null && !scene.belongsTo(hit, editingGroupId!))
          ? null
          : _selectionTarget(hit);
      final additive =
          HardwareKeyboard.instance.isShiftPressed || multiSelectMode;
      if (target == null) {
        _marqueeStart = _start;
        _marqueeBase = {..._selectedIds};
        if (!additive) _marqueeBase = {};
        if (!additive) _setSelection([]);
      } else if (additive) {
        final next = {..._selectedIds};
        if (!next.remove(target)) next.add(target);
        _setSelection(next);
        _togglingSelection = true;
      } else if (!_selectedIds.contains(target)) {
        _setSelection([target]);
      }
      _gestureSelectionBounds = selectionBounds;
      if (canEditSelection && _gestureSelectionBounds != null) {
        _prepareSnapping();
      }
      if (event.kind == PointerDeviceKind.touch) {
        final local = event.localPosition, global = event.position;
        _longPressTimer = Timer(
          const Duration(milliseconds: 500),
          () => contextAt(local, global),
        );
      }
      _notify(toolbar: true);
    } else if (_gestureTool == EditorTool.pen ||
        _gestureTool == EditorTool.highlighter) {
      selectedId = null;
      _sampler = StrokeSampler(tolerance: camera.worldTolerance(.65));
      _gestureStrokeStyle = StrokeStyle(
        color: activeStrokeColor,
        width: activeStrokeWidth,
      );
      _gestureHighlighterOpacity = highlighterOpacity;
      previewPath = Path();
      _appendStrokeSamples(_sampler!.add(Point2.zero));
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
    if (_pressScreen != null && screen.distanceTo(_pressScreen!) > 6) {
      _longPressTimer?.cancel();
    }
    final world = _world(event.localPosition);
    switch (_gestureTool) {
      case EditorTool.text || EditorTool.sticky:
        break;
      case EditorTool.eraser || EditorTool.segmentEraser:
        _erase(_world(Offset(_lastScreen!.x, _lastScreen!.y)), world);
      case EditorTool.pan:
        camera = _boundedCamera(camera.pan(screen - _lastScreen!));
      case EditorTool.select:
        if (_marqueeStart != null) {
          _updateMarquee(world);
        } else if (_handleAnchor != null) {
          _updateHandle(world);
        } else if (canEditSelection && !_togglingSelection) {
          _updateMove(world - _start!);
        }
      case EditorTool.pen || EditorTool.highlighter:
        final relative = world - _start!;
        _appendStrokeSamples(_sampler!.add(relative));
        _strokeTail = _points.length >= 50000 || relative == _points.last
            ? null
            : (Path()
                ..moveTo(_points.last.x, _points.last.y)
                ..lineTo(relative.x, relative.y));
      case EditorTool.rectangle ||
          EditorTool.ellipse ||
          EditorTool.triangle ||
          EditorTool.line ||
          EditorTool.arrow ||
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
    if (_gestureTool == EditorTool.line || _gestureTool == EditorTool.arrow) {
      if (start.distanceTo(end) * camera.zoom < 2) return null;
      return DocumentElement(
        id: ElementId('preview'),
        transform: Transform2.translation(start.x, start.y),
        content: _gestureTool == EditorTool.arrow
            ? ArrowElementContent(
                start: Point2.zero,
                end: Point2(dx, dy),
                style: StrokeStyle(
                  color: activeStrokeColor,
                  width: strokeWidth,
                  dashed: dashed,
                ),
                headLength: math.max(12, strokeWidth * 4),
                headWidth: math.max(10, strokeWidth * 3),
                heads: arrowHeads,
              )
            : LineElementContent(
                start: Point2.zero,
                end: Point2(dx, dy),
                style: StrokeStyle(
                  color: activeStrokeColor,
                  width: strokeWidth,
                  dashed: dashed,
                ),
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
        fillColor: fillColor,
        stroke: StrokeStyle(
          color: activeStrokeColor,
          width: strokeWidth,
          dashed: dashed,
        ),
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
      } else if (_gestureTool == EditorTool.pen ||
          _gestureTool == EditorTool.highlighter) {
        _appendStrokeSamples(
          _sampler!.finish(_world(event.localPosition) - _start!),
        );
        session.insert(
          StrokeElementContent(
            points: _points,
            style: _gestureStrokeStyle!,
            kind: _gestureTool == EditorTool.highlighter
                ? StrokeKind.highlighter
                : StrokeKind.pen,
            highlighterOpacity: _gestureTool == EditorTool.highlighter
                ? _gestureHighlighterOpacity
                : null,
          ),
          transform: Transform2.translation(_start!.x, _start!.y),
        );
        _refreshScene();
      } else if (_gestureTool == EditorTool.select) {
        if (_marqueeStart != null) {
          _updateMarquee(_world(event.localPosition));
        } else if (canEditSelection && !_togglingSelection) {
          final delta = _world(event.localPosition) - _start!;
          if (delta.distanceTo(Point2.zero) * camera.zoom >= 2) {
            if (_handleAnchor != null) {
              _updateHandle(_world(event.localPosition));
              if (_framePreviewBounds != null && selectedId != null) {
                session.resize(selectedId!, _framePreviewBounds!);
              } else if (_previewWorld != null) {
                session.transformMany(_selectedIds, _previewWorld!);
              }
            } else {
              _updateMove(delta);
              session.transformMany(
                _selectedIds,
                Transform2.translation(moveDelta.x, moveDelta.y),
              );
            }
            _refreshScene();
          }
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
    _longPressTimer?.cancel();
    _longPressTimer = null;
    marqueeBounds = null;
    _marqueeStart = null;
    _marqueeBase = {};
    _togglingSelection = false;
    _gestureSelectionBounds = null;
    _snapCandidates = const [];
    snapGuides = const [];
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
    _sampler = null;
    _strokeTail = null;
    _gestureStrokeStyle = null;
    previewPath = null;
    previewElement = null;
    moveDelta = Point2.zero;
    if (notify) _notify();
  }

  void deleteSelection() {
    if (readOnly || !inputEnabled) return;
    cancelGesture(notify: false);
    if (canEditSelection && session.deleteMany(_selectedIds)) _refreshScene();
    _notify(toolbar: true);
  }

  void undo() {
    if (readOnly || !inputEnabled || clipboardBusy) return;
    cancelGesture(notify: false);
    if (session.undo()) _refreshScene();
    _notify(toolbar: true);
  }

  void redo() {
    if (readOnly || !inputEnabled || clipboardBusy) return;
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
    clipboard.removeListener(_clipboardChanged);
    if (_ownsClipboard) clipboard.dispose();
    onContextMenu = null;
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
    if (c.hasSelection &&
        (c.moveDelta != Point2.zero || c._previewWorld != null)) {
      final visibleIds = visible.map((e) => e.id).toSet();
      visible = c.scene.paintOrder
          .where(
            (e) => visibleIds.contains(e.id) || c._selectedTree.contains(e.id),
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
      final followsSelection = c._selectedTree.contains(element.id);
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
    if ((c._gestureTool == EditorTool.pen ||
            c._gestureTool == EditorTool.highlighter) &&
        c._start != null) {
      canvas.save();
      canvas.translate(c._start!.x - origin.x, c._start!.y - origin.y);
      paintFreehandPath(
        canvas,
        c.previewPath!,
        style: c._gestureStrokeStyle!,
        highlighter: c._gestureTool == EditorTool.highlighter,
        opacity: c._gestureTool == EditorTool.highlighter
            ? c._gestureHighlighterOpacity
            : 1,
        tail: c._strokeTail,
        dot: c._points.length == 1 && c._strokeTail == null
            ? c._points.first
            : null,
      );
      canvas.restore();
    } else if (c.previewElement case final element?) {
      _element(canvas, element, element.transform, c.previewPath!, origin);
    }
    if (c.selectedIds.length > 1) {
      final paint = Paint()
        ..color = const Color(0x994464f6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / c.camera.zoom;
      for (final id in c.selectedIds) {
        final b = c.scene.boundsOf(id);
        final preview = c._previewWorld?.mapBounds(b) ?? b;
        canvas.drawRect(
          Rect.fromLTRB(
            preview.left - origin.x + c.moveDelta.x,
            preview.top - origin.y + c.moveDelta.y,
            preview.right - origin.x + c.moveDelta.x,
            preview.bottom - origin.y + c.moveDelta.y,
          ),
          paint,
        );
      }
    }
    final locked = <ElementId>{};
    for (final element in visible) {
      DocumentElement? current = element;
      while (current != null) {
        if (current.locked) locked.add(current.id);
        current = c.session.document.byId[current.parentId];
      }
    }
    final unit = 1 / c.camera.zoom;
    for (final id in locked) {
      final bounds = c.scene.boundsOf(id);
      final center = Offset(bounds.right - origin.x, bounds.top - origin.y);
      canvas.drawCircle(
        center,
        10 * unit,
        Paint()..color = const Color(0xff4464f6),
      );
      final stroke = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5 * unit
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + Offset(0, 2 * unit),
            width: 9 * unit,
            height: 7 * unit,
          ),
          Radius.circular(unit),
        ),
        stroke,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: center - Offset(0, 2 * unit),
          width: 6 * unit,
          height: 7 * unit,
        ),
        math.pi,
        math.pi,
        false,
        stroke,
      );
    }
    final selected = c.selectedId;
    if (c.hasSelection &&
        (c.tool == EditorTool.select || c.tool == EditorTool.pan)) {
      final originalBounds = c._framePreviewBounds == null || selected == null
          ? c.selectionBounds!
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
    if (c.marqueeBounds case final b?) {
      final rect = Rect.fromLTRB(
        b.left - origin.x,
        b.top - origin.y,
        b.right - origin.x,
        b.bottom - origin.y,
      );
      canvas.drawRect(rect, Paint()..color = const Color(0x224464f6));
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xff4464f6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / c.camera.zoom,
      );
    }
    final guidePaint = Paint()
      ..color = const Color(0xffe34e9a)
      ..strokeWidth = 1 / c.camera.zoom;
    for (final guide in c.snapGuides) {
      canvas.drawLine(
        guide.vertical
            ? Offset(guide.position - origin.x, guide.start - origin.y)
            : Offset(guide.start - origin.x, guide.position - origin.y),
        guide.vertical
            ? Offset(guide.position - origin.x, guide.end - origin.y)
            : Offset(guide.end - origin.x, guide.position - origin.y),
        guidePaint,
      );
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
