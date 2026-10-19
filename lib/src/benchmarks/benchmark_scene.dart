import 'dart:math' as math;
import 'dart:collection';

import '../geometry/geometry.dart';

enum ShapeKind { rectangle, ellipse, triangle }

sealed class BenchmarkContent {
  const BenchmarkContent();
}

final class ShapeContent extends BenchmarkContent {
  const ShapeContent(this.kind);
  final ShapeKind kind;
}

final class StrokeContent extends BenchmarkContent {
  StrokeContent(Iterable<Point2> points, {this.highlighter = false})
    : points = List.unmodifiable(points) {
    if (this.points.isEmpty) throw ArgumentError('A stroke needs points.');
  }

  final List<Point2> points;
  final bool highlighter;
}

final class TextContent extends BenchmarkContent {
  const TextContent(this.text, {this.sticky = false, this.rtl = false});
  final String text;
  final bool sticky;
  final bool rtl;
}

final class ArrowContent extends BenchmarkContent {
  const ArrowContent(this.start, this.end);
  final Point2 start;
  final Point2 end;

  List<Point2> get points {
    final delta = end - start;
    final angle = math.atan2(delta.y, delta.x);
    return [
      start,
      end,
      end - Point2(math.cos(angle - 0.5), math.sin(angle - 0.5)) * 12,
      end,
      end - Point2(math.cos(angle + 0.5), math.sin(angle + 0.5)) * 12,
    ];
  }
}

final class ImageContent extends BenchmarkContent {
  const ImageContent(this.assetId);
  final String assetId;
}

final class GroupContent extends BenchmarkContent {
  const GroupContent();
}

/// Synthetic scene data for Spike A; this is not the portable document schema.
final class BenchmarkNode {
  BenchmarkNode({
    required this.id,
    required this.localBounds,
    required this.content,
    this.parentId,
    this.transform = Transform2.identity,
    this.color = 0xff2563eb,
    this.strokeWidth = 2,
  }) {
    if (id.isEmpty || !strokeWidth.isFinite || strokeWidth < 0) {
      throw ArgumentError('Invalid benchmark node.');
    }
    if ((content is ShapeContent ||
            content is TextContent ||
            content is ImageContent) &&
        (localBounds.width == 0 || localBounds.height == 0)) {
      throw ArgumentError(
        'Renderable rectangles must have positive dimensions.',
      );
    }
  }

  final String id;
  final String? parentId;
  final Transform2 transform;
  final Bounds2 localBounds;
  final BenchmarkContent content;
  final int color;
  final double strokeWidth;

  BenchmarkNode withTransform(Transform2 value) => BenchmarkNode(
    id: id,
    parentId: parentId,
    transform: value,
    localBounds: localBounds,
    content: content,
    color: color,
    strokeWidth: strokeWidth,
  );
}

final class ResolvedNode {
  ResolvedNode(this.node, this.worldTransform)
    : worldBounds = worldTransform.mapBounds(
        node.localBounds.inflate(node.strokeWidth / 2),
      ),
      worldInverse = worldTransform.inverse();

  final BenchmarkNode node;
  final Transform2 worldTransform;
  final Transform2 worldInverse;
  final Bounds2 worldBounds;
}

final class BenchmarkScene {
  factory BenchmarkScene(Iterable<BenchmarkNode> source) {
    final nodes = List<BenchmarkNode>.unmodifiable(source);
    final byId = <String, BenchmarkNode>{};
    final children = <String?, List<BenchmarkNode>>{};
    for (final node in nodes) {
      if (byId.containsKey(node.id)) {
        throw ArgumentError('Duplicate node: ${node.id}');
      }
      byId[node.id] = node;
      children.putIfAbsent(node.parentId, () => []).add(node);
    }
    for (final node in nodes) {
      if (node.parentId != null &&
          byId[node.parentId]?.content is! GroupContent) {
        throw ArgumentError('Missing or invalid parent for ${node.id}.');
      }
    }
    final stack = <(BenchmarkNode, Transform2)>[
      for (final root in (children[null] ?? <BenchmarkNode>[]).reversed)
        (root, Transform2.identity),
    ];
    final resolved = <ResolvedNode>[];
    final worlds = <String, Transform2>{};
    var visited = 0;
    while (stack.isNotEmpty) {
      final (node, parentWorld) = stack.removeLast();
      final world = parentWorld * node.transform;
      worlds[node.id] = world;
      world.inverse();
      visited++;
      if (node.content is! GroupContent) {
        resolved.add(ResolvedNode(node, world));
      }
      for (final child in (children[node.id] ?? <BenchmarkNode>[]).reversed) {
        stack.add((child, world));
      }
    }
    if (visited != nodes.length) throw ArgumentError('Parent cycle detected.');
    final nodeIndices = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i};
    final paintIndices = {
      for (var i = 0; i < resolved.length; i++) resolved[i].node.id: i,
    };
    return BenchmarkScene._(
      _ChunkedList.of(nodes),
      _ChunkedList.of(resolved),
      nodeIndices,
      paintIndices,
      children.map(
        (id, values) =>
            MapEntry(id, List.unmodifiable(values.map((n) => n.id))),
      ),
      _ChunkedList.of(nodes.map((n) => worlds[n.id]!)),
      null,
    );
  }

  BenchmarkScene._(
    this.nodes,
    this.paintOrder,
    this._nodeIndices,
    this._paintIndices,
    this._children,
    this._worlds,
    this.delta,
  );

  final List<BenchmarkNode> nodes;
  final List<ResolvedNode> paintOrder;
  final Map<String, int> _nodeIndices;
  final Map<String, int> _paintIndices;
  final Map<String?, List<String>> _children;
  final _ChunkedList<Transform2> _worlds;
  final Object identity = Object();
  final SceneDelta? delta;

  int? paintIndex(String id) => _paintIndices[id];

  BenchmarkScene translated(String id, Point2 worldDelta) {
    final i = _nodeIndices[id];
    if (i == null) throw ArgumentError.value(id, 'id');
    if (worldDelta == Point2.zero) return this;
    final node = nodes[i];
    final parent = node.parentId == null
        ? Transform2.identity
        : _worlds[_nodeIndices[node.parentId]!];
    return transformed({
      id: (Transform2.translation(worldDelta.x, worldDelta.y) * _worlds[i])
          .relativeTo(parent),
    });
  }

  /// Immutable transform-only delta. Structural replacement remains explicit.
  /// Copies affected 128-entry chunks and their directory, never scene history.
  BenchmarkScene transformed(Map<String, Transform2> transforms) {
    for (final id in transforms.keys) {
      if (!_nodeIndices.containsKey(id)) throw ArgumentError.value(id, 'id');
    }
    if (transforms.entries.every(
      (entry) => nodes[_nodeIndices[entry.key]!].transform == entry.value,
    )) {
      return this;
    }
    final affected = <String>{};
    final pending = transforms.keys.toList();
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (affected.add(id)) pending.addAll(_children[id] ?? const []);
    }
    // Only affected roots are traversed; each descendant resolves once.
    final roots = affected.where(
      (id) => !affected.contains(nodes[_nodeIndices[id]!].parentId),
    );
    final stack = <(String, Transform2)>[
      for (final id in roots)
        (
          id,
          nodes[_nodeIndices[id]!].parentId == null
              ? Transform2.identity
              : _worlds[_nodeIndices[nodes[_nodeIndices[id]!].parentId]!],
        ),
    ];
    final nodeChanges = <int, BenchmarkNode>{};
    final worldChanges = <int, Transform2>{};
    final paintChanges = <int, ResolvedNode>{};
    while (stack.isNotEmpty) {
      final (id, parentWorld) = stack.removeLast();
      final i = _nodeIndices[id]!;
      final node = transforms.containsKey(id)
          ? nodes[i].withTransform(transforms[id]!)
          : nodes[i];
      final world = parentWorld * node.transform;
      nodeChanges[i] = node;
      worldChanges[i] = world;
      final paint = _paintIndices[id];
      if (paint != null) paintChanges[paint] = ResolvedNode(node, world);
      for (final child in _children[id] ?? const <String>[]) {
        stack.add((child, world));
      }
    }
    return BenchmarkScene._(
      (nodes as _ChunkedList<BenchmarkNode>).updated(nodeChanges),
      (paintOrder as _ChunkedList<ResolvedNode>).updated(paintChanges),
      _nodeIndices,
      _paintIndices,
      _children,
      _worlds.updated(worldChanges),
      SceneDelta._(
        identity,
        List.unmodifiable(paintChanges.keys),
        affected.length,
      ),
    );
  }
}

final class SceneDelta {
  const SceneDelta._(this.baseIdentity, this.paintIndices, this.resolvedCount);
  final Object baseIdentity;
  final List<int> paintIndices;
  final int resolvedCount;
}

final class _ChunkedList<T> extends ListBase<T> {
  _ChunkedList._(this._chunks, this._length);
  factory _ChunkedList.of(Iterable<T> source) {
    final values = source.toList(growable: false);
    return _ChunkedList._([
      for (var i = 0; i < values.length; i += 128)
        List.unmodifiable(values.sublist(i, math.min(i + 128, values.length))),
    ], values.length);
  }
  final List<List<T>> _chunks;
  final int _length;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Immutable scene');
  @override
  T operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _chunks[index ~/ 128][index % 128];
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Immutable scene');
  _ChunkedList<T> updated(Map<int, T> changes) {
    final chunks = List<List<T>>.of(_chunks);
    final copied = <int, List<T>>{};
    for (final entry in changes.entries) {
      final block = entry.key ~/ 128;
      final values = copied.putIfAbsent(block, () => List<T>.of(chunks[block]));
      values[entry.key % 128] = entry.value;
    }
    for (final entry in copied.entries) {
      chunks[entry.key] = List.unmodifiable(entry.value);
    }
    return _ChunkedList._(chunks, _length);
  }
}
