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

  ElementId insert(
    ElementContent content, {
    Transform2 transform = Transform2.identity,
    DocumentFontReference? font,
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
      _Change([], [
        _Positioned(_document.elements.length, element),
      ], font: font),
    );
    _nextId = candidate;
    return id;
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
      assets: _document.assets,
      // Font declarations remain available to both sides of undo history.
      fontReferences: change.font == null
          ? _document.fontReferences
          : [
              ...?_document.fontReferences,
              if (!(_document.fontReferences ?? <DocumentFontReference>[]).any(
                (font) => font.id == change.font!.id,
              ))
                change.font!,
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
  _Change(this.before, this.after, {this.font});
  final DocumentFontReference? font;
  final List<_Positioned> before;
  final List<_Positioned> after;
}

final class _Positioned {
  _Positioned(this.index, this.element);
  final int index;
  final DocumentElement element;
}
