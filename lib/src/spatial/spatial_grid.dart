import '../geometry/geometry.dart';

/// Rebuildable broad-phase index; returned indices retain source paint order.
final class SpatialGrid {
  SpatialGrid(Iterable<Bounds2> bounds, {this.cellSize = 256})
    : _bounds = List.of(bounds) {
    if (!cellSize.isFinite || cellSize <= 0) {
      throw ArgumentError.value(cellSize, 'cellSize');
    }
    for (var i = 0; i < _bounds.length; i++) {
      final (left, top, right, bottom) = _cellsFor(_bounds[i]);
      if ((right - left + 1) * (bottom - top + 1) > _maxCellsPerEntry) {
        _overflow.add(i);
        continue;
      }
      for (var x = left; x <= right; x++) {
        for (var y = top; y <= bottom; y++) {
          _cells.putIfAbsent((x, y), () => []).add(i);
        }
      }
    }
  }

  static const _maxCellsPerEntry = 256;
  static const _maxQueryCells = 4096;
  final double cellSize;
  final List<Bounds2> _bounds;
  final _cells = <(int, int), List<int>>{};
  final _overflow = <int>[];

  void validateBounds(Bounds2 bounds) {
    _cellsFor(bounds);
  }

  /// Update one committed element; camera motion never rebuilds this index.
  void update(int index, Bounds2 bounds) {
    RangeError.checkValidIndex(index, _bounds);
    final next = _cellsFor(bounds);
    final previous = _cellsFor(_bounds[index]);
    void visit((int, int, int, int) cells, void Function((int, int)) action) {
      final (left, top, right, bottom) = cells;
      for (var x = left; x <= right; x++) {
        for (var y = top; y <= bottom; y++) {
          action((x, y));
        }
      }
    }

    bool oversized((int, int, int, int) cells) =>
        (cells.$3 - cells.$1 + 1) * (cells.$4 - cells.$2 + 1) >
        _maxCellsPerEntry;
    if (oversized(previous)) {
      _overflow.remove(index);
    } else {
      visit(previous, (cell) {
        final bucket = _cells[cell]!;
        bucket.remove(index);
        if (bucket.isEmpty) _cells.remove(cell);
      });
    }
    _bounds[index] = bounds;
    if (oversized(next)) {
      _overflow.add(index);
    } else {
      visit(next, (cell) => _cells.putIfAbsent(cell, () => []).add(index));
    }
  }

  (int, int, int, int) _cellsFor(Bounds2 bounds) {
    final cells = [
      bounds.left / cellSize,
      bounds.top / cellSize,
      bounds.right / cellSize,
      bounds.bottom / cellSize,
    ];
    // Bound integer arithmetic equally on native and JavaScript runtimes.
    if (cells.any((cell) => !cell.isFinite || cell.abs() > 1000000000)) {
      throw ArgumentError('Bounds exceed the spatial grid coordinate range.');
    }
    return (
      cells[0].floor(),
      cells[1].floor(),
      cells[2].floor(),
      cells[3].floor(),
    );
  }

  List<int> query(Bounds2 area) {
    final (left, top, right, bottom) = _cellsFor(area);
    if ((right - left + 1) * (bottom - top + 1) > _maxQueryCells) {
      return [
        for (var i = 0; i < _bounds.length; i++)
          if (_bounds[i].intersects(area)) i,
      ];
    }
    final candidates = <int>{..._overflow};
    for (var x = left; x <= right; x++) {
      for (var y = top; y <= bottom; y++) {
        candidates.addAll(_cells[(x, y)] ?? const []);
      }
    }
    return (candidates.where((i) => _bounds[i].intersects(area)).toList()
      ..sort());
  }
}
