import '../document/document.dart';
import '../document/document_geometry.dart';
import '../document/document_settings.dart';
import '../document/element.dart';
import '../geometry/geometry.dart';

/// Owns committed snapshots and bounded inverse changes for one open board.
/// Pointer previews belong to the editor and never enter this history.
final class BoardSession {
  BoardSession({BoardDocument? document, this.historyLimit = 100})
    : _document =
          document ?? BoardDocument(id: 'board', revision: 0, elements: []) {
    if (historyLimit < 0) {
      throw ArgumentError.value(historyLimit, 'historyLimit');
    }
    _initialIds = _document.byId.keys.toSet();
    DocumentGeometry(_document);
  }

  final int historyLimit;
  BoardDocument _document;
  late final Set<ElementId> _initialIds;
  final List<_Change> _undo = [];
  final List<_Change> _redo = [];
  int _nextId = 1;

  BoardDocument get document => _document;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void setTitle(String title) {
    if (_document.title == title) return;
    _document = BoardDocument(
      id: _document.id,
      schemaVersion: _document.schemaVersion,
      revision: _document.revision,
      workspaceId: _document.workspaceId,
      title: title,
      canvasSettings: _document.canvasSettings,
      assets: _document.assets,
      fontReferences: _document.fontReferences,
      metadata: _document.metadata,
      elements: _document.elements,
    );
  }

  ElementId insert(
    ElementContent content, {
    Transform2 transform = Transform2.identity,
    DocumentFontReference? font,
    DocumentAssetReference? asset,
  }) {
    var candidate = _nextId;
    late ElementId id;
    do {
      if (candidate > maximumDocumentRevision) {
        throw StateError('Element identity range exhausted.');
      }
      id = ElementId('element-${candidate++}');
    } while (_initialIds.contains(id));
    final element = DocumentElement(
      id: id,
      content: content,
      transform: transform,
    );
    _commit(
      _Change(
        [],
        [_Positioned(_document.elements.length, element)],
        font: font,
        asset: asset,
      ),
    );
    _nextId = candidate;
    return id;
  }

  bool rotate(ElementId id, double radians) {
    final element = _document.byId[id];
    if (element == null ||
        radians == 0 ||
        _isLocked(element) ||
        _hasLockedDescendant(element)) {
      return false;
    }
    final geometry = DocumentGeometry(_document);
    final localBounds = switch (element.content) {
      ShapeElementContent(:final bounds) => bounds,
      TextElementContent(:final bounds) => bounds,
      StickyNoteElementContent(:final bounds) => bounds,
      ImageElementContent(:final bounds) => bounds,
      ContainerFrameElementContent(:final bounds) => bounds,
      ExportFrameElementContent(:final bounds) => bounds,
      StrokeElementContent(:final points) => Bounds2.fromPoints(points),
      LineElementContent(:final start, :final end) => Bounds2.fromPoints([
        start,
        end,
      ]),
      _ => null,
    };
    final localCenter = localBounds?.center ?? Point2.zero;
    final center = geometry.worldTransformOf(id).apply(localCenter);
    final parent = element.parentId;
    final parentWorld = parent == null
        ? Transform2.identity
        : geometry.worldTransformOf(parent);
    final currentWorld = geometry.worldTransformOf(id);
    final rotation =
        Transform2.translation(center.x, center.y) *
        Transform2.rotation(radians) *
        Transform2.translation(-center.x, -center.y);
    final newWorld = rotation * currentWorld;
    final newLocal = newWorld.relativeTo(parentWorld);
    final index = _document.elements.indexOf(element);
    _commit(
      _Change(
        [_Positioned(index, element)],
        [_Positioned(index, element.copyWith(transform: newLocal))],
      ),
    );
    return true;
  }

  bool setWorldTransform(ElementId id, Transform2 worldTransform) {
    final element = _document.byId[id];
    if (element == null ||
        _isLocked(element) ||
        _hasLockedDescendant(element)) {
      return false;
    }
    final parent = element.parentId;
    final local = parent == null
        ? worldTransform
        : worldTransform.relativeTo(
            DocumentGeometry(_document).worldTransformOf(parent),
          );
    if (local == element.transform) return false;
    final index = _document.elements.indexOf(element);
    _commit(
      _Change(
        [_Positioned(index, element)],
        [_Positioned(index, element.copyWith(transform: local))],
      ),
    );
    return true;
  }

  bool resize(ElementId id, Bounds2 newBounds) {
    final element = _document.byId[id];
    if (element == null || _isLocked(element)) {
      return false;
    }
    final content = element.content;
    final ElementContent? updatedContent = switch (content) {
      ImageElementContent(:final assetId) => ImageElementContent(
        assetId: assetId,
        bounds: newBounds,
      ),
      ShapeElementContent(:final kind, :final stroke, :final fillColor) =>
        ShapeElementContent(
          kind: kind,
          bounds: newBounds,
          stroke: stroke,
          fillColor: fillColor,
        ),
      TextElementContent(
        :final text,
        :final style,
        :final direction,
        :final alignment,
        :final sizing,
      ) =>
        TextElementContent(
          text: text,
          bounds: newBounds,
          style: style,
          direction: direction,
          alignment: alignment,
          sizing: sizing,
        ),
      StickyNoteElementContent(
        :final text,
        :final style,
        :final backgroundColor,
        :final direction,
        :final alignment,
        :final sizing,
      ) =>
        StickyNoteElementContent(
          text: text,
          bounds: newBounds,
          style: style,
          backgroundColor: backgroundColor,
          direction: direction,
          alignment: alignment,
          sizing: sizing,
        ),
      ContainerFrameElementContent(:final label) =>
        ContainerFrameElementContent(bounds: newBounds, label: label),
      ExportFrameElementContent(
        :final label,
        :final outputWidth,
        :final outputHeight,
      ) =>
        ExportFrameElementContent(
          bounds: newBounds,
          label: label,
          outputWidth: outputWidth,
          outputHeight: outputHeight,
        ),
      _ => null,
    };
    if (updatedContent == null) return false;
    final index = _document.elements.indexOf(element);
    _commit(
      _Change(
        [_Positioned(index, element)],
        [_Positioned(index, element.copyWith(content: updatedContent))],
      ),
    );
    return true;
  }

  ElementId? duplicate(ElementId id, [Point2? offset]) {
    final element = _document.byId[id];
    if (element == null) return null;
    final delta = offset ?? Point2(24, 24);
    final subtree = <ElementId>{};
    final pending = [element];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      subtree.add(current.id);
      pending.addAll(_document.childrenOf(current.id));
    }
    final ids = {for (final oldId in subtree) oldId: _allocateId()};
    final geometry = DocumentGeometry(_document);
    final world =
        Transform2.translation(delta.x, delta.y) *
        geometry.worldTransformOf(id);
    final transform = element.parentId == null
        ? world
        : world.relativeTo(geometry.worldTransformOf(element.parentId!));
    final after = <_Positioned>[];
    for (final current in _document.elements) {
      if (!subtree.contains(current.id)) continue;
      after.add(
        _Positioned(
          _document.elements.length + after.length,
          DocumentElement(
            id: ids[current.id]!,
            parentId: current.id == id
                ? current.parentId
                : ids[current.parentId],
            transform: current.id == id ? transform : current.transform,
            locked: current.id == id ? false : current.locked,
            opacity: current.opacity,
            content: current.content,
          ),
        ),
      );
    }
    _commit(_Change([], after));
    return ids[id];
  }

  /// Updates frame metadata as one undoable operation; omitted values persist.
  bool updateFrame(
    ElementId id, {
    String? label,
    Bounds2? bounds,
    int? outputWidth,
    int? outputHeight,
  }) {
    final content = _document.byId[id]?.content;
    final ElementContent updated;
    if (content is ExportFrameElementContent) {
      final frame = ExportFrameElementContent(
        bounds: bounds ?? content.bounds,
        label: label ?? content.label,
        outputWidth: outputWidth ?? content.outputWidth,
        outputHeight: outputHeight ?? content.outputHeight,
      );
      if (frame.bounds == content.bounds &&
          frame.label == content.label &&
          frame.outputWidth == content.outputWidth &&
          frame.outputHeight == content.outputHeight) {
        return false;
      }
      updated = frame;
    } else if (content is ContainerFrameElementContent) {
      if (outputWidth != null || outputHeight != null) return false;
      final frame = ContainerFrameElementContent(
        bounds: bounds ?? content.bounds,
        label: label ?? content.label,
      );
      if (frame.bounds == content.bounds && frame.label == content.label) {
        return false;
      }
      updated = frame;
    } else {
      return false;
    }
    return updateContent(id, updated);
  }

  /// Changes ownership without changing world geometry or relative source order.
  bool reparent(ElementId id, ElementId? parentId) {
    final element = _document.byId[id];
    if (element == null ||
        element.parentId == parentId ||
        _isLocked(element) ||
        _hasLockedDescendant(element)) {
      return false;
    }
    if (parentId != null) {
      final owner = _document.byId[parentId];
      if (owner == null || !owner.content.canOwnChildren || _isLocked(owner)) {
        return false;
      }
      DocumentElement? ancestor = owner;
      while (ancestor != null) {
        if (ancestor.id == id) return false;
        ancestor = _document.byId[ancestor.parentId];
      }
    }
    final geometry = DocumentGeometry(_document);
    final world = geometry.worldTransformOf(id);
    final local = parentId == null
        ? world
        : world.relativeTo(geometry.worldTransformOf(parentId));
    final index = _document.elements.indexOf(element);
    final updated = DocumentElement(
      id: id,
      parentId: parentId,
      transform: local,
      locked: element.locked,
      opacity: element.opacity,
      revision: element.revision,
      content: element.content,
    );
    _commit(
      _Change([_Positioned(index, element)], [_Positioned(index, updated)]),
    );
    return true;
  }

  bool updateContent(ElementId id, ElementContent content) {
    final element = _document.byId[id];
    if (element == null || _isLocked(element)) return false;
    final index = _document.elements.indexOf(element);
    _commit(
      _Change(
        [_Positioned(index, element)],
        [_Positioned(index, element.copyWith(content: content))],
      ),
    );
    return true;
  }

  /// Converts a world displacement into the owner's local coordinate system.
  bool translate(ElementId id, Point2 worldDelta) {
    final element = _document.byId[id];
    if (element == null ||
        worldDelta == Point2.zero ||
        _isLocked(element) ||
        _hasLockedDescendant(element)) {
      return false;
    }
    final parent = element.parentId;
    final inverse = parent == null
        ? Transform2.identity
        : DocumentGeometry(_document).worldTransformOf(parent).inverse();
    final dx = inverse.a * worldDelta.x + inverse.c * worldDelta.y;
    final dy = inverse.b * worldDelta.x + inverse.d * worldDelta.y;
    final transform = Transform2(
      a: element.transform.a,
      b: element.transform.b,
      c: element.transform.c,
      d: element.transform.d,
      tx: element.transform.tx + dx,
      ty: element.transform.ty + dy,
    );
    if (transform == element.transform) return false;
    final index = _document.elements.indexOf(element);
    _commit(
      _Change(
        [_Positioned(index, element)],
        [_Positioned(index, element.copyWith(transform: transform))],
      ),
    );
    return true;
  }

  /// Deletes an ownership subtree as one operation, preserving source order.
  bool delete(ElementId id) {
    final element = _document.byId[id];
    if (element == null || _isLocked(element)) return false;
    final removedIds = <ElementId>{};
    final pending = [element];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current.locked) return false;
      removedIds.add(current.id);
      pending.addAll(_document.childrenOf(current.id));
    }
    _commit(
      _Change([
        for (var i = 0; i < _document.elements.length; i++)
          if (removedIds.contains(_document.elements[i].id))
            _Positioned(i, _document.elements[i]),
      ], []),
    );
    return true;
  }

  /// Replaces editable leaves or deletes complete unlocked ownership subtrees.
  /// A gesture publishes one revision, retaining source order and sparse undo.
  bool replaceElements(Map<ElementId, List<ElementContent>> replacements) {
    final before = <_Positioned>[];
    final after = <_Positioned>[];
    final removed = <ElementId>{};
    final accepted = <ElementId, List<ElementContent>>{};
    for (final entry in replacements.entries) {
      final element = _document.byId[entry.key];
      if (element == null ||
          _isLocked(element) ||
          _hasLockedDescendant(element)) {
        continue;
      }
      if (entry.value.isNotEmpty && element.content.canOwnChildren) continue;
      accepted[entry.key] = entry.value;
      if (entry.value.isEmpty) {
        final pending = [element];
        while (pending.isNotEmpty) {
          final current = pending.removeLast();
          removed.add(current.id);
          pending.addAll(_document.childrenOf(current.id));
        }
      }
    }
    var outputIndex = 0;
    for (var i = 0; i < _document.elements.length; i++) {
      final element = _document.elements[i];
      final replacement = accepted[element.id];
      if (removed.contains(element.id) || replacement != null) {
        before.add(_Positioned(i, element));
        if (!removed.contains(element.id) && replacement != null) {
          for (var part = 0; part < replacement.length; part++) {
            final id = part == 0 ? element.id : _allocateId();
            after.add(
              _Positioned(
                outputIndex++,
                DocumentElement(
                  id: id,
                  parentId: element.parentId,
                  transform: element.transform,
                  locked: element.locked,
                  opacity: element.opacity,
                  content: replacement[part],
                ),
              ),
            );
          }
        }
      } else {
        outputIndex++;
      }
    }
    if (before.isEmpty) return false;
    _commit(_Change(before, after));
    return true;
  }

  /// Top-level selection roots in paint order; selecting an owner never applies
  /// a second transform to one of its already-selected descendants.
  List<ElementId> selectionRoots(Iterable<ElementId> ids) {
    final selected = ids.where(_document.byId.containsKey).toSet();
    return [
      for (final element in _document.preorder)
        if (selected.contains(element.id) &&
            !_hasSelectedAncestor(element, selected))
          element.id,
    ];
  }

  bool _hasSelectedAncestor(DocumentElement element, Set<ElementId> selected) {
    var parent = element.parentId;
    while (parent != null) {
      if (selected.contains(parent)) return true;
      parent = _document.byId[parent]!.parentId;
    }
    return false;
  }

  bool canEdit(ElementId id) {
    final element = _document.byId[id];
    return element != null &&
        !_isLocked(element) &&
        !_hasLockedDescendant(element);
  }

  List<ElementId>? _editableRoots(Iterable<ElementId> ids) {
    final requested = ids.toSet();
    if (requested.isEmpty ||
        requested.any((id) => !_document.byId.containsKey(id))) {
      return null;
    }
    final roots = selectionRoots(requested);
    return roots.every(canEdit) ? roots : null;
  }

  /// Styles eligible drawings in selected ownership subtrees as one operation.
  /// Geometry, hierarchy and non-drawing content remain unchanged.
  bool styleMany(
    Iterable<ElementId> ids, {
    int? strokeColor,
    double? strokeWidth,
    int? fillColor,
    bool clearFill = false,
    bool? dashed,
    ArrowHeadStyle? arrowHeads,
    double? highlighterOpacity,
  }) {
    if (strokeColor != null && (strokeColor < 0 || strokeColor > 0xffffffff)) {
      throw ArgumentError.value(strokeColor, 'strokeColor');
    }
    if (strokeWidth != null && (!strokeWidth.isFinite || strokeWidth <= 0)) {
      throw ArgumentError.value(strokeWidth, 'strokeWidth');
    }
    if (fillColor != null && (fillColor < 0 || fillColor > 0xffffffff)) {
      throw ArgumentError.value(fillColor, 'fillColor');
    }
    if (clearFill && fillColor != null) {
      throw ArgumentError('Choose a fill color or clear the fill, not both.');
    }
    if (highlighterOpacity != null &&
        (!highlighterOpacity.isFinite ||
            highlighterOpacity < 0 ||
            highlighterOpacity > 1)) {
      throw ArgumentError.value(highlighterOpacity, 'highlighterOpacity');
    }
    final roots = _editableRoots(ids);
    if (roots == null) return false;
    final members = _subtreeIds(roots);
    final hasStrokeChange =
        strokeColor != null || strokeWidth != null || dashed != null;
    StrokeStyle restyle(StrokeStyle previous) {
      final color = strokeColor ?? previous.color;
      final width = strokeWidth ?? previous.width;
      final dash = dashed ?? previous.dashed;
      if (color == previous.color &&
          width == previous.width &&
          dash == previous.dashed) {
        return previous;
      }
      return StrokeStyle(color: color, width: width, dashed: dash);
    }

    final changes = <ElementId, DocumentElement>{};
    for (final element in _document.elements) {
      if (!members.contains(element.id)) continue;
      final content = element.content;
      ElementContent updated = content;
      switch (content) {
        case ShapeElementContent():
          var stroke = content.stroke;
          if (hasStrokeChange) {
            stroke = restyle(
              stroke ??
                  StrokeStyle(color: content.fillColor ?? 0xff202d46, width: 3),
            );
          }
          final fill = clearFill ? null : (fillColor ?? content.fillColor);
          if (stroke == null && fill == null) {
            throw ArgumentError('A shape needs a fill or a stroke.');
          }
          if (!identical(stroke, content.stroke) || fill != content.fillColor) {
            updated = ShapeElementContent(
              kind: content.kind,
              bounds: content.bounds,
              stroke: stroke,
              fillColor: fill,
            );
          }
        case LineElementContent():
          final style = restyle(content.style);
          if (!identical(style, content.style)) {
            updated = LineElementContent(
              start: content.start,
              end: content.end,
              style: style,
            );
          }
        case ArrowElementContent():
          final style = restyle(content.style);
          final heads = arrowHeads ?? content.heads;
          if (!identical(style, content.style) || heads != content.heads) {
            updated = ArrowElementContent(
              start: content.start,
              end: content.end,
              style: style,
              headLength: content.headLength,
              headWidth: content.headWidth,
              heads: heads,
            );
          }
        case StrokeElementContent():
          final style = restyle(content.style);
          final opacity = content.kind == StrokeKind.highlighter
              ? (highlighterOpacity ?? content.highlighterOpacity)
              : content.highlighterOpacity;
          if (!identical(style, content.style) ||
              opacity != content.highlighterOpacity) {
            updated = StrokeElementContent(
              points: content.points,
              kind: content.kind,
              style: style,
              highlighterOpacity: opacity,
            );
          }
        default:
          break;
      }
      if (!identical(updated, content)) {
        changes[element.id] = element.copyWith(content: updated);
      }
    }
    if (changes.isEmpty) return false;
    _commitElements([
      for (final element in _document.elements) changes[element.id] ?? element,
    ]);
    return true;
  }

  bool transformMany(Iterable<ElementId> ids, Transform2 worldDelta) {
    final roots = _editableRoots(ids);
    if (roots == null || worldDelta == Transform2.identity) return false;
    final geometry = DocumentGeometry(_document);
    final changes = <ElementId, DocumentElement>{};
    for (final id in roots) {
      final element = _document.byId[id]!;
      final world = worldDelta * geometry.worldTransformOf(id);
      final local = element.parentId == null
          ? world
          : world.relativeTo(geometry.worldTransformOf(element.parentId!));
      if (local != element.transform) {
        changes[id] = element.copyWith(transform: local);
      }
    }
    if (changes.isEmpty) return false;
    _commitElements([
      for (final element in _document.elements) changes[element.id] ?? element,
    ]);
    return true;
  }

  bool translateMany(Map<ElementId, Point2> worldDeltas) {
    final roots = _editableRoots(worldDeltas.keys);
    if (roots == null) return false;
    final geometry = DocumentGeometry(_document);
    final changes = <ElementId, DocumentElement>{};
    for (final id in roots) {
      final delta = worldDeltas[id]!;
      if (delta == Point2.zero) continue;
      final element = _document.byId[id]!;
      final world =
          Transform2.translation(delta.x, delta.y) *
          geometry.worldTransformOf(id);
      final local = element.parentId == null
          ? world
          : world.relativeTo(geometry.worldTransformOf(element.parentId!));
      if (local != element.transform) {
        changes[id] = element.copyWith(transform: local);
      }
    }
    if (changes.isEmpty) return false;
    _commitElements([
      for (final element in _document.elements) changes[element.id] ?? element,
    ]);
    return true;
  }

  bool deleteMany(Iterable<ElementId> ids) {
    final roots = _editableRoots(ids);
    if (roots == null) return false;
    final removed = _subtreeIds(roots);
    _commitElements([
      for (final element in _document.elements)
        if (!removed.contains(element.id)) element,
    ]);
    return true;
  }

  Set<ElementId> _subtreeIds(Iterable<ElementId> roots) {
    final result = <ElementId>{};
    final pending = roots.toList();
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!result.add(id)) continue;
      pending.addAll(_document.childrenOf(id).map((element) => element.id));
    }
    return result;
  }

  List<ElementId> duplicateMany(
    Iterable<ElementId> ids, [
    Point2? worldOffset,
  ]) {
    final roots = _editableRoots(ids);
    if (roots == null) return const [];
    final members = _subtreeIds(roots);
    final rootSet = roots.toSet();
    final remap = {for (final id in members) id: _allocateId()};
    final geometry = DocumentGeometry(_document);
    final offset = worldOffset ?? Point2(24, 24);
    final translation = Transform2.translation(offset.x, offset.y);
    final copies = <DocumentElement>[];
    for (final element in _document.elements) {
      if (!members.contains(element.id)) continue;
      var transform = element.transform;
      if (rootSet.contains(element.id)) {
        final world = translation * geometry.worldTransformOf(element.id);
        transform = element.parentId == null
            ? world
            : world.relativeTo(geometry.worldTransformOf(element.parentId!));
      }
      copies.add(
        DocumentElement(
          id: remap[element.id]!,
          parentId: rootSet.contains(element.id)
              ? element.parentId
              : remap[element.parentId],
          transform: transform,
          content: element.content,
          locked: element.locked,
          opacity: element.opacity,
        ),
      );
    }
    _commitElements([..._document.elements, ...copies]);
    return [for (final id in roots) remap[id]!];
  }

  bool canGroup(Iterable<ElementId> ids) {
    final roots = _editableRoots(ids);
    if (roots == null || roots.length < 2) return false;
    final parent = _document.byId[roots.first]!.parentId;
    return roots.every((id) => _document.byId[id]!.parentId == parent);
  }

  /// The new group occupies the frontmost selected sibling's layer. Selected
  /// siblings keep their relative order; cross-owner grouping is rejected.
  ElementId? group(Iterable<ElementId> ids) {
    final roots = selectionRoots(ids);
    if (!canGroup(ids)) return null;
    final selected = roots.toSet();
    final parent = _document.byId[roots.first]!.parentId;
    final groupId = _allocateId();
    var last = 0;
    final elements = <DocumentElement>[];
    for (var i = 0; i < _document.elements.length; i++) {
      final element = _document.elements[i];
      if (selected.contains(element.id)) {
        last = i;
        elements.add(_withParent(element, groupId, element.transform));
      } else {
        elements.add(element);
      }
    }
    elements.insert(
      last + 1,
      DocumentElement(
        id: groupId,
        parentId: parent,
        content: const GroupElementContent(),
      ),
    );
    _commitElements(elements);
    return groupId;
  }

  List<ElementId> ungroup(Iterable<ElementId> ids) {
    final roots = _editableRoots(ids);
    if (roots == null ||
        roots.any(
          (id) => _document.byId[id]!.content is! GroupElementContent,
        )) {
      return const [];
    }
    var elements = _document.elements.toList();
    final selected = <ElementId>[];
    for (final id in roots) {
      final group = _document.byId[id]!;
      final children = _document.childrenOf(id);
      final removed = {id, ...children.map((element) => element.id)};
      final groupIndex = elements.indexWhere((element) => element.id == id);
      final insertion = elements
          .take(groupIndex)
          .where((element) => !removed.contains(element.id))
          .length;
      elements = elements
          .where((element) => !removed.contains(element.id))
          .toList();
      elements.insertAll(
        insertion,
        children.map(
          (child) => _withParent(
            child,
            group.parentId,
            group.transform * child.transform,
            opacity: group.opacity * child.opacity,
          ),
        ),
      );
      selected.addAll(children.map((element) => element.id));
    }
    _commitElements(elements);
    return selected;
  }

  bool setLockedMany(Iterable<ElementId> ids, bool locked) {
    final requested = ids.toSet();
    if (requested.isEmpty ||
        requested.any((id) => !_document.byId.containsKey(id))) {
      return false;
    }
    final roots = selectionRoots(requested);
    for (final id in roots) {
      final parent = _document.byId[id]!.parentId;
      if (parent != null && _isLocked(_document.byId[parent]!)) return false;
    }
    var changed = false;
    final selected = roots.toSet();
    final next = <DocumentElement>[];
    for (final element in _document.elements) {
      if (selected.contains(element.id) && element.locked != locked) {
        changed = true;
        next.add(element.copyWith(locked: locked));
      } else {
        next.add(element);
      }
    }
    if (!changed) return false;
    _commitElements(next);
    return true;
  }

  bool reorderMany(Iterable<ElementId> ids, String action) {
    if (!const {'front', 'back', 'forward', 'backward'}.contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    final roots = _editableRoots(ids);
    if (roots == null) return false;
    final selected = roots.toSet();
    final parents = roots.map((id) => _document.byId[id]!.parentId).toSet();
    final replacements = <int, DocumentElement>{};
    for (final parent in parents) {
      final positions = <int>[];
      final siblings = <DocumentElement>[];
      for (var i = 0; i < _document.elements.length; i++) {
        if (_document.elements[i].parentId == parent) {
          positions.add(i);
          siblings.add(_document.elements[i]);
        }
      }
      final ordered = siblings.toList();
      if (action == 'front' || action == 'back') {
        final chosen = siblings.where(
          (element) => selected.contains(element.id),
        );
        final others = siblings.where(
          (element) => !selected.contains(element.id),
        );
        ordered
          ..clear()
          ..addAll(action == 'front' ? others : chosen)
          ..addAll(action == 'front' ? chosen : others);
      } else if (action == 'forward') {
        for (var i = ordered.length - 2; i >= 0; i--) {
          if (selected.contains(ordered[i].id) &&
              !selected.contains(ordered[i + 1].id)) {
            final previous = ordered[i];
            ordered[i] = ordered[i + 1];
            ordered[i + 1] = previous;
          }
        }
      } else {
        for (var i = 1; i < ordered.length; i++) {
          if (selected.contains(ordered[i].id) &&
              !selected.contains(ordered[i - 1].id)) {
            final previous = ordered[i];
            ordered[i] = ordered[i - 1];
            ordered[i - 1] = previous;
          }
        }
      }
      for (var i = 0; i < ordered.length; i++) {
        if (ordered[i].id != siblings[i].id) {
          replacements[positions[i]] = ordered[i];
        }
      }
    }
    if (replacements.isEmpty) return false;
    _commitElements([
      for (var i = 0; i < _document.elements.length; i++)
        replacements[i] ?? _document.elements[i],
    ]);
    return true;
  }

  /// Inserts a validated world-rooted forest. Asset bytes must already be durable
  /// in the receiving store; this command only owns immutable declarations.
  List<ElementId> insertFragment(
    BoardDocument fragment, {
    required Point2 offset,
  }) {
    DocumentGeometry(fragment);
    final assets = fragment.assets ?? const <DocumentAssetReference>[];
    final fonts = fragment.fontReferences ?? const <DocumentFontReference>[];
    for (final incoming in assets) {
      final current = _document.assets
          ?.where((asset) => asset.id == incoming.id)
          .firstOrNull;
      if (current != null && !_sameAsset(current, incoming)) {
        throw ArgumentError('Conflicting asset declaration: ${incoming.id}');
      }
    }
    for (final incoming in fonts) {
      final current = _document.fontReferences
          ?.where((font) => font.id == incoming.id)
          .firstOrNull;
      if (current != null &&
          (current.family != incoming.family ||
              current.assetId != incoming.assetId)) {
        throw ArgumentError('Conflicting font declaration: ${incoming.id}');
      }
    }
    if (fragment.elements.isEmpty) return const [];
    final remap = {
      for (final element in fragment.elements) element.id: _allocateId(),
    };
    final translation = Transform2.translation(offset.x, offset.y);
    final copies = [
      for (final element in fragment.elements)
        DocumentElement(
          id: remap[element.id]!,
          parentId: element.parentId == null ? null : remap[element.parentId],
          transform: element.parentId == null
              ? translation * element.transform
              : element.transform,
          content: element.content,
          opacity: element.opacity,
          locked: element.locked,
        ),
    ];
    _commitElements(
      [..._document.elements, ...copies],
      assets: assets,
      fonts: fonts,
    );
    return [
      for (final element in fragment.childrenOf(null)) remap[element.id]!,
    ];
  }

  bool _sameAsset(DocumentAssetReference a, DocumentAssetReference b) =>
      a.mimeType == b.mimeType &&
      a.pixelWidth == b.pixelWidth &&
      a.pixelHeight == b.pixelHeight &&
      a.byteLength == b.byteLength &&
      a.sha256 == b.sha256;

  DocumentElement _withParent(
    DocumentElement element,
    ElementId? parent,
    Transform2 transform, {
    double? opacity,
  }) => DocumentElement(
    id: element.id,
    parentId: parent,
    transform: transform,
    content: element.content,
    locked: element.locked,
    revision: element.revision,
    opacity: opacity ?? element.opacity,
  );

  void _commitElements(
    List<DocumentElement> next, {
    List<DocumentAssetReference> assets = const [],
    List<DocumentFontReference> fonts = const [],
  }) {
    final previousIndex = {
      for (var i = 0; i < _document.elements.length; i++)
        _document.elements[i].id: i,
    };
    final nextIndex = {for (var i = 0; i < next.length; i++) next[i].id: i};
    final affected = <ElementId>{};
    for (var i = 0; i < _document.elements.length; i++) {
      final element = _document.elements[i];
      final index = nextIndex[element.id];
      if (index == null || index != i || !identical(element, next[index])) {
        affected.add(element.id);
      }
    }
    for (final element in next) {
      if (!previousIndex.containsKey(element.id)) affected.add(element.id);
    }
    _commit(
      _Change(
        [
          for (var i = 0; i < _document.elements.length; i++)
            if (affected.contains(_document.elements[i].id))
              _Positioned(i, _document.elements[i]),
        ],
        [
          for (var i = 0; i < next.length; i++)
            if (affected.contains(next[i].id)) _Positioned(i, next[i]),
        ],
        assets: assets,
        fonts: fonts,
      ),
    );
  }

  ElementId _allocateId() {
    while (_nextId <= maximumDocumentRevision) {
      final id = ElementId('element-${_nextId++}');
      if (!_initialIds.contains(id) && !_document.byId.containsKey(id)) {
        return id;
      }
    }
    throw StateError('Element identity range exhausted.');
  }

  /// Explicit board-wide action; manifests stay alive for undo and other uses.
  bool clearAll() {
    if (_document.elements.isEmpty) return false;
    _commit(
      _Change([
        for (var i = 0; i < _document.elements.length; i++)
          _Positioned(i, _document.elements[i]),
      ], []),
    );
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    final change = _undo.last;
    final next = _apply(change, forward: false);
    _undo.removeLast();
    _redo.add(change);
    _document = next;
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    final change = _redo.last;
    final next = _apply(change, forward: true);
    _redo.removeLast();
    _undo.add(change);
    _document = next;
    return true;
  }

  bool _isLocked(DocumentElement element) {
    DocumentElement? current = element;
    while (current != null) {
      if (current.locked) return true;
      current = _document.byId[current.parentId];
    }
    return false;
  }

  bool _hasLockedDescendant(DocumentElement element) {
    final pending = [..._document.childrenOf(element.id)];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current.locked) return true;
      pending.addAll(_document.childrenOf(current.id));
    }
    return false;
  }

  void _commit(_Change change) {
    final next = _apply(change, forward: true);
    _redo.clear();
    if (historyLimit > 0) {
      _undo.add(change);
      if (_undo.length > historyLimit) _undo.removeAt(0);
    }
    _document = next;
  }

  BoardDocument _apply(_Change change, {required bool forward}) {
    if (_document.revision == maximumDocumentRevision) {
      throw StateError('Document revision range exhausted.');
    }
    final revision = _document.revision + 1;
    final remove = forward ? change.before : change.after;
    final insert = forward ? change.after : change.before;
    final affected = remove.map((entry) => entry.element.id).toSet();
    final elements = _document.elements
        .where((element) => !affected.contains(element.id))
        .toList();
    for (final entry in insert) {
      elements.insert(entry.index, entry.element.copyWith(revision: revision));
    }
    final next = BoardDocument(
      id: _document.id,
      schemaVersion: _document.schemaVersion,
      revision: revision,
      workspaceId: _document.workspaceId,
      title: _document.title,
      canvasSettings: _document.canvasSettings,
      // Asset and font declarations remain available to both sides of undo history.
      assets: change.asset == null && change.assets.isEmpty
          ? _document.assets
          : [
              ...?_document.assets,
              for (final asset in [
                if (change.asset != null) change.asset!,
                ...change.assets,
              ])
                if (!(_document.assets ?? const <DocumentAssetReference>[]).any(
                  (current) => current.id == asset.id,
                ))
                  asset,
            ],
      fontReferences: change.font == null && change.fonts.isEmpty
          ? _document.fontReferences
          : [
              ...?_document.fontReferences,
              for (final font in [
                if (change.font != null) change.font!,
                ...change.fonts,
              ])
                if (!(_document.fontReferences ??
                        const <DocumentFontReference>[])
                    .any((current) => current.id == font.id))
                  font,
            ],
      metadata: _document.metadata,
      elements: elements,
    );
    // Validate accumulated owner transforms before changing document or history.
    DocumentGeometry(next);
    return next;
  }
}

final class _Change {
  _Change(
    this.before,
    this.after, {
    this.font,
    this.asset,
    this.assets = const [],
    this.fonts = const [],
  });
  final List<DocumentAssetReference> assets;
  final List<DocumentFontReference> fonts;
  final DocumentFontReference? font;
  final DocumentAssetReference? asset;
  final List<_Positioned> before;
  final List<_Positioned> after;
}

final class _Positioned {
  _Positioned(this.index, this.element);
  final int index;
  final DocumentElement element;
}
