final class TimingSamples {
  static const capacity = 2400;
  TimingSamples({this.limit = capacity}) {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
  }
  final int limit;
  final _stageMicros = <int>[];
  int _next = 0;
  int observed = 0;

  int get count => _stageMicros.length;

  void add(int value) {
    if (value < 0) {
      throw ArgumentError('Frame durations cannot be negative.');
    }
    observed++;
    if (_stageMicros.length < limit) {
      _stageMicros.add(value);
    } else {
      _stageMicros[_next] = value;
      _next = (_next + 1) % limit;
    }
  }

  double? percentileMs(double percentile) {
    if (!percentile.isFinite || percentile <= 0 || percentile > 100) {
      throw ArgumentError.value(percentile, 'percentile');
    }
    if (_stageMicros.isEmpty) return null;
    final sorted = List<int>.of(_stageMicros)..sort();
    final index = (percentile / 100 * sorted.length).ceil() - 1;
    return sorted[index] / 1000;
  }

  void clear() {
    _stageMicros.clear();
    _next = 0;
    observed = 0;
  }

  Map<String, Object?> toJson() => {
    'observed': observed,
    'retained': count,
    'p50Ms': percentileMs(50),
    'p95Ms': percentileMs(95),
    'p99Ms': percentileMs(99),
  };
}

final class FrameSamples {
  static const capacity = TimingSamples.capacity;
  FrameSamples({int limit = capacity})
    : stage = TimingSamples(limit: limit),
      build = TimingSamples(limit: limit),
      raster = TimingSamples(limit: limit),
      totalSpan = TimingSamples(limit: limit);
  final TimingSamples stage;
  final TimingSamples build;
  final TimingSamples raster;
  final TimingSamples totalSpan;

  int get count => stage.count;

  void add({
    required int buildMicros,
    required int rasterMicros,
    int? totalMicros,
  }) {
    if (buildMicros < 0 ||
        rasterMicros < 0 ||
        (totalMicros != null && totalMicros < 0)) {
      throw ArgumentError('Frame durations cannot be negative.');
    }
    stage.add(buildMicros > rasterMicros ? buildMicros : rasterMicros);
    build.add(buildMicros);
    raster.add(rasterMicros);
    if (totalMicros != null) totalSpan.add(totalMicros);
  }

  double? percentileMs(double percentile) => stage.percentileMs(percentile);
  Map<String, Object?> toJson() => {
    'stage': stage.toJson(),
    'build': build.toJson(),
    'raster': raster.toJson(),
    'totalSpan': totalSpan.toJson(),
  };
  void clear() {
    stage.clear();
    build.clear();
    raster.clear();
    totalSpan.clear();
  }
}
