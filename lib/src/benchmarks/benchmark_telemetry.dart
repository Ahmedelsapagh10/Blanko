import 'frame_samples.dart';

/// Feasibility instrumentation owned by the page session, never by the scene.
final class BenchmarkTelemetry {
  BenchmarkTelemetry({this.sampleLimit = TimingSamples.capacity})
    : query = TimingSamples(limit: sampleLimit),
      recordPaint = TimingSamples(limit: sampleLimit),
      updateToPaint = TimingSamples(limit: sampleLimit),
      commit = TimingSamples(limit: sampleLimit),
      pointerToPaint = TimingSamples(limit: sampleLimit);
  final int sampleLimit;
  final TimingSamples query;
  final TimingSamples recordPaint;
  final TimingSamples updateToPaint;
  final TimingSamples commit;
  final TimingSamples pointerToPaint;
  Stopwatch? _pendingPointer;
  Duration? _lastPointerTime;
  int pointerTimestampRegressions = 0;
  int overviewPaints = 0;
  Stopwatch? _firstPaintProbe;
  double? _firstPaintRecordWallMs;

  void beginFirstPaintProbe() {
    _firstPaintRecordWallMs = null;
    _firstPaintProbe = Stopwatch()..start();
  }

  void markPointer(Duration timestamp) {
    if (_lastPointerTime != null && timestamp < _lastPointerTime!) {
      pointerTimestampRegressions++;
    }
    _lastPointerTime = timestamp;
    _pendingPointer ??= Stopwatch()..start();
  }

  final visibleCounts = <int>[];
  Stopwatch? _pendingUpdate;
  bool recording = false;
  int paintCount = 0;

  void markUpdate() {
    if (recording) _pendingUpdate ??= Stopwatch()..start();
  }

  void painted(int visible) {
    final first = _firstPaintProbe;
    if (first != null) {
      _firstPaintRecordWallMs = first.elapsedMicroseconds / 1000;
      _firstPaintProbe = null;
    }
    paintCount++;
    final pointer = _pendingPointer;
    if (pointer != null) {
      pointerToPaint.add(pointer.elapsedMicroseconds);
      _pendingPointer = null;
    }
    if (!recording) return;
    if (visibleCounts.length < sampleLimit) {
      visibleCounts.add(visible);
    }
    final pending = _pendingUpdate;
    if (pending != null) {
      updateToPaint.add(pending.elapsedMicroseconds);
      _pendingUpdate = null;
    }
  }

  Map<String, Object?> toJson() {
    final sorted = List<int>.of(visibleCounts)..sort();
    return {
      'pointerReceiptToPaint': pointerToPaint.toJson(),
      'pointerTimestampRegressions': pointerTimestampRegressions,
      'overviewPaints': overviewPaints,
      'queryCpu': query.toJson(),
      'recordPaintCpu': recordPaint.toJson(),
      'syntheticUpdateToPaint': updateToPaint.toJson(),
      'commitCpu': commit.toJson(),
      'commandToFirstPaintRecordMs': _firstPaintRecordWallMs,
      'paintCount': paintCount,
      'visibleP50': sorted.isEmpty ? null : sorted[(sorted.length / 2).floor()],
      'visibleMax': sorted.isEmpty ? null : sorted.last,
    };
  }

  void clear() {
    _firstPaintProbe = null;
    _firstPaintRecordWallMs = null;
    overviewPaints = 0;
    pointerToPaint.clear();
    pointerTimestampRegressions = 0;
    _lastPointerTime = null;
    _pendingPointer = null;
    query.clear();
    recordPaint.clear();
    updateToPaint.clear();
    commit.clear();
    visibleCounts.clear();
    _pendingUpdate = null;
    paintCount = 0;
  }
}
