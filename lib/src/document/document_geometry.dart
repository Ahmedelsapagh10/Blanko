import '../geometry/geometry.dart';
import 'document.dart';
import 'element.dart';

/// Rebuildable transform lookup owned by one immutable document snapshot.
final class DocumentGeometry {
  factory DocumentGeometry(BoardDocument document) {
    final worlds = <ElementId, Transform2>{};
    final inverses = <ElementId, Transform2>{};
    for (final element in document.preorder) {
      final parentWorld = element.parentId == null
          ? Transform2.identity
          : worlds[element.parentId]!;
      try {
        final world = parentWorld * element.transform;
        final inverse = world.inverse();
        worlds[element.id] = world;
        inverses[element.id] = inverse;
      } on ArgumentError catch (error) {
        throw ArgumentError(
          'Cannot resolve world transform for element ${element.id}: '
          '${error.message}',
        );
      }
    }
    return DocumentGeometry._(
      document,
      Map.unmodifiable(worlds),
      Map.unmodifiable(inverses),
    );
  }

  DocumentGeometry._(this.document, this.worldTransforms, this._worldInverses);

  final BoardDocument document;
  final Map<ElementId, Transform2> worldTransforms;
  final Map<ElementId, Transform2> _worldInverses;

  Transform2 worldTransformOf(ElementId id) => _require(worldTransforms, id);

  Point2 localToWorld(ElementId id, Point2 point) {
    final transform = worldTransformOf(id);
    try {
      return transform.apply(point);
    } on ArgumentError catch (error) {
      throw ArgumentError(
        'Cannot map local point to world for element $id: ${error.message}',
      );
    }
  }

  Point2 worldToLocal(ElementId id, Point2 point) {
    final inverse = _require(_worldInverses, id);
    try {
      return inverse.apply(point);
    } on ArgumentError catch (error) {
      throw ArgumentError(
        'Cannot map world point to local for element $id: ${error.message}',
      );
    }
  }

  Transform2 _require(Map<ElementId, Transform2> transforms, ElementId id) {
    final transform = transforms[id];
    if (transform == null) {
      throw ArgumentError.value(id, 'id', 'Unknown document element.');
    }
    return transform;
  }
}
