import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../geometry/geometry.dart';
import '../viewport/camera.dart';
import 'benchmark_fixtures.dart';
import 'benchmark_fonts.dart';
import 'benchmark_scene.dart';
import 'benchmark_canvas.dart';
import 'benchmark_telemetry.dart';
import 'frame_samples.dart';
import 'scene_renderer.dart';

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key, this.startupClock});
  final Stopwatch? startupClock;

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _transformation = TransformationController();
  final _samples = FrameSamples(
    limit: (_phase02 || _phase03) ? 12000 : FrameSamples.capacity,
  );
  final _telemetry = BenchmarkTelemetry(
    sampleLimit: (_phase02 || _phase03) ? 12000 : TimingSamples.capacity,
  );
  final _moveDelta = ValueNotifier<Point2>(Point2.zero);
  final _loads = <String, Map<String, Object?>>{};
  Completer<bool>? _ready;
  Completer<Map<String, Object?>>? _runCompletion;
  int? _movePointer;
  int? _movingIndex;
  Point2? _moveStartWorld;
  bool _moveMode = false;
  bool _suiteActive = false;
  bool _suiteStarted = false;
  int _lifecycleChanges = 0;
  int _runLifecycleChanges = 0;
  int _warmupMicros = 0;
  String _workload = 'camera';
  Size _runViewport = Size.zero;
  Map<String, Object?>? _hitProbe;
  static const _optimized = bool.fromEnvironment(
    'PHASE01_OPTIMIZED',
    defaultValue: true,
  );
  static const _tiles = bool.fromEnvironment(
    'PHASE02_TILES',
    defaultValue: false,
  );
  static const _phase02 = bool.fromEnvironment('PHASE02_SUITE');
  static const _phase03 = bool.fromEnvironment('PHASE03_SUITE');
  static const _coldAudit = bool.fromEnvironment('PHASE03_COLD_AUDIT');
  static const _recovery = bool.fromEnvironment('PHASE03_RECOVERY');
  static const _dirtyRepair = bool.fromEnvironment('WB_DIRTY_REPAIR');
  static const _retained = bool.fromEnvironment('WB_RETAINED_RANGES');
  static const _layers = bool.fromEnvironment('WB_RETAINED_LAYERS');
  static const _interleaved = bool.fromEnvironment('WB_LAYER_INTERLEAVED');
  static const _retainedExperiment = bool.fromEnvironment(
    'WB_RETAINED_EXPERIMENT',
  );
  final _frameSeries = <List<int>>[];
  final _commitSeries = <List<int>>[];
  int _editTick = 0;
  int _nextEditMicros = 0;
  List<String> _editIds = const [];
  static const _soakSeconds = int.fromEnvironment(
    'PHASE02_SOAK_SECONDS',
    defaultValue: 180,
  );
  final _intervals = TimingSamples(
    limit: (_phase02 || _phase03) ? 12000 : TimingSamples.capacity,
  );
  int? _previousVsync;
  Timer? _overviewTimer;
  Timer? _inputReportTimer;
  Timer? _startupTimer;
  bool? _viewFocused;
  int _focusChanges = 0;
  int _runFocusChanges = 0;
  int _layerCachePeak = 0;
  int _pictureCachePeak = 0;
  static const _autostartDelay = int.fromEnvironment(
    'PHASE01_AUTORUN_DELAY_MS',
  );
  static const _diagnostics = bool.fromEnvironment('PHASE01_DIAGNOSTICS');
  static const _autorun = bool.fromEnvironment('PHASE0_AUTORUN');
  late final AnimationController _sweep;
  SceneDistribution _distribution = SceneDistribution.sparse;
  BenchmarkFixture? _fixture;
  BenchmarkScene? _scene;
  SceneRenderer? _renderer;
  String? _error;
  String? _selected;
  String? _result;
  Size _viewportSize = Size.zero;
  int _generation = 0;
  final _coldSamples = FrameSamples();
  int? _coldStart;
  int? _coldEnd;
  int? _runStart;
  int? _runEnd;
  bool _loading = true;
  bool _recording = false;
  Camera? _sweepOrigin;
  Timer? _flushTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sweep =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..addListener(_animateCamera)
          ..addStatusListener(_onSweepStatus);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _load(_distribution);
  }

  Future<void> _load(SceneDistribution distribution) async {
    _overviewTimer?.cancel();
    _inputReportTimer?.cancel();
    _startupTimer?.cancel();
    final generation = ++_generation;
    if (_ready?.isCompleted == false) _ready!.complete(false);
    _ready = Completer<bool>();
    final loadClock = Stopwatch()..start();
    _coldSamples.clear();
    _coldStart =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    _coldEnd = null;
    final loadMetrics = <String, Object?>{};
    _cancelRun();
    _cancelMove();
    final old = _renderer;
    setState(() {
      _distribution = distribution;
      _renderer = null;
      _fixture = null;
      _scene = null;
      _loading = true;
      _error = null;
      _selected = null;
      _result = null;
    });
    old?.dispose();
    try {
      // Let the loading state paint before preparing the synthetic scene.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _generation) return;
      final fixtureClock = Stopwatch()..start();
      final fixture = BenchmarkFixture.generate(distribution);
      loadMetrics['fixtureMs'] = fixtureClock.elapsedMicroseconds / 1000;
      final prepareClock = Stopwatch()..start();
      final renderer = await SceneRenderer.create(
        fixture.scene,
        cacheOverview: _optimized && !_retainedExperiment,
        cacheTiles: _tiles && !_retainedExperiment,
        recoverTiles: _recovery,
        repairTiles: _dirtyRepair,
        retainRanges: _retained,
        retainLayers: _layers,
        imageSide: distribution == SceneDistribution.imageHeavy ? 2048 : 1024,
      );
      loadMetrics['rendererPrepareMs'] =
          prepareClock.elapsedMicroseconds / 1000;
      loadMetrics['fonts'] = BenchmarkFonts.instance.report;
      if (!mounted || generation != _generation) {
        renderer.dispose();
        return;
      }
      setState(() {
        _fixture = fixture;
        _scene = fixture.scene;
        _renderer = renderer;
        _loading = false;
      });
      _loads[distribution.name] = loadMetrics;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation) return;
        _resetCamera();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _generation) return;
          _coldEnd = SchedulerBinding
              .instance
              .currentSystemFrameTimeStamp
              .inMicroseconds;
          loadMetrics['loadToInteractiveMs'] =
              loadClock.elapsedMicroseconds / 1000;
          if (widget.startupClock != null && _loads.length == 1) {
            loadMetrics['dartEntryToInteractiveMs'] =
                widget.startupClock!.elapsedMicroseconds / 1000;
          }
          _ready?.complete(true);
          debugPrint(
            'PHASE0_READY ${jsonEncode({'scene': distribution.name, ...loadMetrics})}',
          );
          if (_autorun && !_suiteStarted) {
            _suiteStarted = true;
            _startupTimer = Timer(Duration(milliseconds: _autostartDelay), () {
              if (mounted && generation == _generation) unawaited(_runSuite());
            });
          }
        });
        WidgetsBinding.instance.scheduleFrame();
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Could not prepare the benchmark: $error';
      });
      if (_ready?.isCompleted == false) _ready!.complete(false);
    }
  }

  Camera get _camera {
    final matrix = _transformation.value;
    return Camera(
      translation: Point2(matrix.storage[12], matrix.storage[13]),
      zoom: math
          .sqrt(
            matrix.storage[0] * matrix.storage[0] +
                matrix.storage[1] * matrix.storage[1],
          )
          .clamp(Camera.minZoom, Camera.maxZoom),
    );
  }

  void _setCamera(Camera camera) {
    _transformation.value = Matrix4.identity()
      ..setEntry(0, 0, camera.zoom)
      ..setEntry(1, 1, camera.zoom)
      ..setEntry(2, 2, camera.zoom)
      ..setEntry(0, 3, camera.translation.x)
      ..setEntry(1, 3, camera.translation.y);
  }

  void _resetCamera() {
    final focus = _fixture?.initialFocus;
    if (focus == null) return;
    _setCamera(
      Camera(
        translation: Point2(
          _viewportSize.width / 2 - focus.x,
          _viewportSize.height / 2 - focus.y,
        ),
      ),
    );
  }

  Future<Map<String, Object?>> _startRun({
    String workload = 'camera',
    bool warmup = false,
    int? seconds,
  }) {
    if (_renderer == null || _viewportSize.isEmpty) {
      return Future.value({'cancelled': true});
    }
    _cancelRun();
    _cancelMove();
    _samples.clear();
    _frameSeries.clear();
    _commitSeries.clear();
    _editTick = 0;
    _nextEditMicros = 0;
    _intervals.clear();
    _previousVsync = null;
    _telemetry.clear();
    if (_retainedExperiment) _telemetry.beginFirstPaintProbe();
    _telemetry.recording = false;
    _runCompletion = Completer<Map<String, Object?>>();
    _workload = workload;
    _warmupMicros = warmup ? 1000000 : 0;
    _runViewport = _viewportSize;
    _runLifecycleChanges = _lifecycleChanges;
    _runFocusChanges = _focusChanges;
    _layerCachePeak = 0;
    _pictureCachePeak = 0;
    if (workload.startsWith('edit')) {
      final view = _camera.worldViewport(
        _viewportSize.width,
        _viewportSize.height,
      );
      final visible = _renderer!.index.query(view);
      final candidates = visible.toList()..sort();
      final count = workload == 'editMulti' || workload == 'editInterleaved'
          ? candidates.length.clamp(0, 16)
          : candidates.length.clamp(0, 1);
      _editIds = [
        for (var n = 0; n < count; n++)
          _renderer!
              .scene
              .paintOrder[candidates[workload == 'editInterleaved' && count > 1
                  ? (n * (candidates.length - 1) / (count - 1)).round()
                  : n]]
              .node
              .id,
      ];
      if (workload == 'editOffscreen') {
        _editIds = [_renderer!.scene.paintOrder.last.node.id];
        final node = _renderer!.scene.paintOrder.last;
        final next = _renderer!.scene.translated(
          node.node.id,
          Point2(
            20000 - node.worldBounds.center.x,
            20000 - node.worldBounds.center.y,
          ),
        );
        _renderer!.synchronize(next);
        _scene = next;
      }
    }
    _renderer!.setRetainedActiveIndices(
      workload.startsWith('edit')
          ? _editIds.map((id) => _renderer!.scene.paintIndex(id)!)
          : workload == 'stress'
          ? [_renderer!.scene.paintIndex('element-0')!]
          : const [],
    );
    if (_retainedExperiment) _renderer!.resetRetained();
    if (workload == 'movement') {
      _movingIndex = 0;
      _selected = _renderer!.scene.paintOrder.first.node.id;
      final center = _renderer!.scene.paintOrder.first.worldBounds.center;
      _setCamera(
        Camera(
          translation: Point2(
            _viewportSize.width / 2 - center.x,
            _viewportSize.height / 2 - center.y,
          ),
        ),
      );
    }
    _sweepOrigin = _camera;
    _runStart = null;
    _runEnd = null;
    setState(() {
      _recording = true;
      _result = null;
    });
    _sweep.duration = Duration(
      seconds:
          (seconds ?? (workload == 'movement' ? 5 : 10)) + (warmup ? 1 : 0),
    );
    _sweep.forward(from: 0);
    return _runCompletion!.future;
  }

  void _animateCamera() {
    final origin = _sweepOrigin;
    if (!_recording || origin == null) return;
    // Engine timings and raw scheduler timestamps share a clock on native/web.
    final elapsed = _sweep.lastElapsedDuration?.inMicroseconds ?? 0;
    if (elapsed >= _warmupMicros && elapsed > 0) {
      if (_runStart == null) _runViewport = _viewportSize;
      _runStart ??=
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      _telemetry.recording = true;
    }
    final phase = _sweep.value * math.pi * 2;
    if (_workload.startsWith('edit')) {
      // Fixed camera; commit bursts at 10 Hz, never an unbounded catch-up loop.
      if (elapsed >= _nextEditMicros) {
        _nextEditMicros = elapsed + 100000;
        _editTick++;
        _telemetry.markUpdate();
        _applyEdits(_editIds, _editTick.isEven ? .25 : -.25);
        _renderer!.cacheChanges.value++;
      }
      return;
    }
    if (_workload.startsWith('cold') || _workload == 'reopen') {
      return;
    }

    if (_workload == 'overview') {
      _telemetry.markUpdate();
      _setCamera(
        origin
            .zoomAt(
              Point2(_viewportSize.width / 2, _viewportSize.height / 2),
              0.22313,
            )
            .pan(Point2(math.sin(phase) * 50, math.cos(phase) * 30)),
      );
      return;
    }
    _telemetry.markUpdate();
    final anchor = Point2(_viewportSize.width / 2, _viewportSize.height / 2);
    if (_workload == 'staticRedraw') {
      _renderer!.cacheChanges.value++;
      return;
    }
    if (_workload == 'normalEditing') {
      _setCamera(
        origin.pan(Point2(math.sin(phase) * 100, math.cos(phase) * 50)),
      );
      return;
    }
    if (_workload == 'zoomIn' || _workload == 'zoomOut') {
      final t = _workload == 'zoomIn' ? _sweep.value : 1 - _sweep.value;
      _setCamera(origin.zoomAt(anchor, math.exp(-1.5 + 3 * t)));
      return;
    }
    if (_workload == 'oscillation') {
      _setCamera(origin.zoomAt(anchor, 1 + math.sin(phase * 12) * 0.02));
      return;
    }
    if (_workload == 'movement') {
      _moveDelta.value = Point2(
        _sweep.value * 120 + math.sin(phase) * 100,
        math.sin(phase) * 60,
      );
      return;
    }
    _setCamera(
      origin
          .zoomAt(anchor, origin.zoom * math.exp(math.sin(phase) * 1.5))
          .pan(
            Point2(
              math.sin(phase * 2) * _viewportSize.width * 0.15,
              (math.cos(phase) - 1) * _viewportSize.height * 0.1,
            ),
          ),
    );
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    if (_phase03 && _coldStart != null) {
      for (final timing in timings) {
        final start = timing.timestampInMicroseconds(ui.FramePhase.buildStart);
        if (start >= _coldStart! && (_coldEnd == null || start <= _coldEnd!)) {
          _coldSamples.add(
            buildMicros: timing.buildDuration.inMicroseconds,
            rasterMicros: timing.rasterDuration.inMicroseconds,
            totalMicros: timing.totalSpan.inMicroseconds,
          );
        }
      }
    }
    final runStart = _runStart;
    if (!_recording || runStart == null) return;
    for (final timing in timings) {
      final start = timing.timestampInMicroseconds(ui.FramePhase.buildStart);
      if (start < runStart || (_runEnd != null && start > _runEnd!)) continue;
      final vsync = timing.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      if (_previousVsync != null && vsync > _previousVsync!) {
        _intervals.add(vsync - _previousVsync!);
      }
      _previousVsync = vsync;
      _layerCachePeak = math.max(_layerCachePeak, timing.layerCacheBytes);
      _pictureCachePeak = math.max(_pictureCachePeak, timing.pictureCacheBytes);
      if (_phase03 && _frameSeries.length < 12000) {
        _frameSeries.add([
          start,
          timing.buildDuration.inMicroseconds,
          timing.rasterDuration.inMicroseconds,
          timing.totalSpan.inMicroseconds,
        ]);
      }
      _samples.add(
        buildMicros: timing.buildDuration.inMicroseconds,
        rasterMicros: timing.rasterDuration.inMicroseconds,
        totalMicros: timing.totalSpan.inMicroseconds,
      );
    }
  }

  void _onSweepStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_recording) return;
    _runEnd =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    if (_workload == 'movement') _commitMove();
    _telemetry.recording = false;
    // The engine reports timings in batches after rendering.
    _flushTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || !_recording) return;
      final report = <String, Object?>{
        'compiler': !kIsWeb
            ? 'native'
            : const bool.fromEnvironment('dart.tool.dart2wasm')
            ? 'dart2wasm'
            : 'dart2js',
        'optimized': _optimized,
        'recovery': _recovery,
        'dirtyRepair': _dirtyRepair,
        'retainedExperiment': _retainedExperiment,
        'retainedEnabled': _retained,
        'retained': _renderer!.retainedStatistics,
        'layersEnabled': _layers,
        'layers': _renderer!.layerStatistics,
        if (_retainedExperiment && _workload.startsWith('edit'))
          'activeEditIds': _editIds,
        if (_retainedExperiment && _workload.startsWith('edit'))
          'activeEditPaintIndices': [
            for (final id in _editIds) _renderer!.scene.paintIndex(id)!,
          ],
        if (_phase03) 'frameSeriesMicros': _frameSeries,
        if (_phase03) 'commitSeriesMicros': _commitSeries,
        if (_phase03)
          'commitSeriesColumns': [
            'schedulerTime',
            'totalCpu',
            'geometryCpu',
            'synchronizationCpu',
            'indexCpu',
            'invalidationCpu',
            'validationCpu',
            'resolvedCount',
            'synchronizedCount',
          ],
        if (_phase03) 'editCount': _editTick,
        'tilesEnabled': _tiles,
        'tiles': _renderer!.tileStatistics,
        'textLayouts': _renderer!.textLayoutCount,
        'frameVsyncIntervals': _intervals.toJson(),
        'preparation': _renderer!.preparation,
        'overviewPrepareMs': _renderer!.overviewPrepareMicros / 1000,
        'overviewBytes': _renderer!.overviewBytes,
        'scene': _distribution.name,
        'workload': _workload,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'mode': kProfileMode
            ? 'profile'
            : kReleaseMode
            ? 'release'
            : 'debug',
        'viewport': {
          'canvasWidth': _viewportSize.width,
          'canvasHeight': _viewportSize.height,
          'windowWidth': MediaQuery.sizeOf(context).width,
          'windowHeight': MediaQuery.sizeOf(context).height,
          'dpr': MediaQuery.devicePixelRatioOf(context),
        },
        'viewportChanged': _runViewport != _viewportSize,
        'lifecycleChanges': _lifecycleChanges - _runLifecycleChanges,
        'viewFocusChanges': _focusChanges - _runFocusChanges,
        'lastObservedViewFocused': _viewFocused,
        'engineLayerCachePeakBytes': _layerCachePeak,
        'enginePictureCachePeakBytes': _pictureCachePeak,
        'warmupMs': _warmupMicros / 1000,
        'frames': _samples.toJson(),
        'cpu': _telemetry.toJson(),
        'load': {
          ...?_loads[_distribution.name],
          if (_phase03) 'coldLoadFrames': _coldSamples.toJson(),
        },
        'hitTest': _hitProbe,
        'indexUpdateMicros': _workload == 'movement'
            ? _renderer!.lastIndexUpdateMicros
            : null,
        'imageSide': _distribution == SceneDistribution.imageHeavy
            ? 2048
            : 1024,
        'imageOriginals': 4,
        'imageReferences': 100,
        'decodedPixelBytes': _renderer!.imageBytes,
      };
      setState(() {
        _recording = false;
        _result = _samples.count == 0
            ? 'No engine frame timings received. Run in profile mode on a target device.'
            : '${_samples.count} frames · slower of build/raster: '
                  'P50 ${_samples.percentileMs(50)!.toStringAsFixed(2)} ms · '
                  'P95 ${_samples.percentileMs(95)!.toStringAsFixed(2)} ms · '
                  'P99 ${_samples.percentileMs(99)!.toStringAsFixed(2)} ms';
      });
      debugPrint('PHASE0_RESULT ${jsonEncode(report)}');
      if (_runCompletion?.isCompleted == false) {
        _runCompletion!.complete(report);
      }
    });
  }

  void _cancelRun() {
    _flushTimer?.cancel();
    _sweep.stop();
    _telemetry.recording = false;
    _recording = false;
    _sweepOrigin = null;
    if (_runCompletion?.isCompleted == false) {
      _runCompletion!.complete({'cancelled': true});
    }
    _cancelMove();
  }

  Map<String, Object?> _probeHits() {
    final renderer = _renderer!;
    final timings = TimingSamples();
    final candidates = <int>[];
    var hits = 0;
    for (var i = 0; i < 288; i++) {
      final point = i.isEven
          ? renderer.scene.paintOrder[(i * 37) % 10000].worldBounds.center
          : _camera.viewportToWorld(
              Point2(
                (i * 73 % 1000) / 1000 * _viewportSize.width,
                (i * 137 % 1000) / 1000 * _viewportSize.height,
              ),
            );
      final clock = Stopwatch()..start();
      final hit = renderer.hitTest(
        point,
        worldTolerance: _camera.worldTolerance(6),
      );
      if (i >= 32) {
        timings.add(clock.elapsedMicroseconds);
        candidates.add(renderer.lastHitCandidates);
        if (hit != null) hits++;
      }
    }
    candidates.sort();
    return {
      'cpu': timings.toJson(),
      'hits': hits,
      'queries': 256,
      'candidateP95': candidates[(candidates.length * 0.95).ceil() - 1],
    };
  }

  Future<void> _runSuite() async {
    if (_suiteActive) return;
    if (_coldAudit) {
      await _runColdAudit();
      return;
    }
    if (_phase02 || _phase03) {
      await _runPhase02();
      return;
    }
    setState(() {
      _suiteActive = true;
    });
    var runs = 0;
    try {
      for (final distribution in SceneDistribution.values.where(
        (d) => d != SceneDistribution.normal,
      )) {
        if (distribution != _distribution) await _load(distribution);
        if (!mounted || !await _ready!.future) return;
        _resetCamera();
        _hitProbe = _probeHits();
        for (final workload in ['camera', 'movement']) {
          final report = await _startRun(workload: workload, warmup: true);
          if (!mounted || report['cancelled'] == true) return;
          runs++;
        }
      }
      // Controlled omissions isolate text/image recording cost in the dense scene.
      await _load(SceneDistribution.dense);
      if (!mounted || !await _ready!.future) return;
      _hitProbe = _probeHits();
      for (final workload in ['withoutText', 'withoutImages']) {
        _resetCamera();
        final report = await _startRun(workload: workload, warmup: true);
        if (!mounted || report['cancelled'] == true) return;
        runs++;
      }
      if (_diagnostics) {
        await _load(SceneDistribution.dense);
        if (!mounted || !await _ready!.future) return;
        _resetCamera();
        await _startRun(workload: 'overview', warmup: true);
        runs++;
        await _runDiagnostics();
      }
      debugPrint('PHASE0_SUITE_DONE ${jsonEncode({'runs': runs})}');
    } catch (error, stack) {
      debugPrint('PHASE0_SUITE_FAILED $error\n$stack');
    } finally {
      if (mounted) {
        setState(() {
          _suiteActive = false;
        });
      }
    }
  }

  Future<void> _runColdAudit() async {
    setState(() => _suiteActive = true);
    try {
      for (final distribution in [
        SceneDistribution.normal,
        SceneDistribution.dense,
      ]) {
        for (var session = 0; session < 2; session++) {
          final old = _renderer;
          final lifecycleBefore = _lifecycleChanges;
          final openClock = Stopwatch()..start();
          // The historical loader paints before its post-frame camera reset.
          // Normalize zoom now so it cannot prewarm the next scale bucket.
          _resetCamera();
          await _load(distribution);
          if (!mounted || !await _ready!.future) return;
          if (!mounted) return;
          final pixelRatio = MediaQuery.devicePixelRatioOf(context);
          _coldEnd = null;
          final renderer = _renderer!;
          final initialViewport = _viewportSize;
          Future<void> prepareViewport() => renderer.prepareTiles(
            _camera.worldViewport(_viewportSize.width, _viewportSize.height),
            _camera.zoom * pixelRatio,
          );
          await prepareViewport();
          await WidgetsBinding.instance.endOfFrame;
          final openWall = openClock.elapsedMicroseconds / 1000;
          _coldEnd = SchedulerBinding
              .instance
              .currentSystemFrameTimeStamp
              .inMicroseconds;
          await Future<void>.delayed(const Duration(seconds: 1));
          final openingFrames = _coldSamples.toJson();
          final operations = <Map<String, Object?>>[];
          Future<void> measure(String name, VoidCallback action) async {
            _coldSamples.clear();
            _coldStart = SchedulerBinding
                .instance
                .currentSystemFrameTimeStamp
                .inMicroseconds;
            _coldEnd = null;
            final before = Map<String, Object?>.of(renderer.tileStatistics!);
            final clock = Stopwatch()..start();
            action();
            renderer.cacheChanges.value++;
            await prepareViewport();
            await WidgetsBinding.instance.endOfFrame;
            final wallMs = clock.elapsedMicroseconds / 1000;
            _coldEnd = SchedulerBinding
                .instance
                .currentSystemFrameTimeStamp
                .inMicroseconds;
            await Future<void>.delayed(const Duration(seconds: 1));
            operations.add({
              'operation': name,
              'commandToCacheAndFrameworkPaintMs': wallMs,
              'frames': _coldSamples.toJson(),
              'before': before,
              'after': renderer.tileStatistics,
            });
          }

          await measure(
            'firstZoomBucket',
            () => _setCamera(
              _camera.zoomAt(
                Point2(_viewportSize.width / 2, _viewportSize.height / 2),
                1.01,
              ),
            ),
          );
          final view = _camera.worldViewport(
            _viewportSize.width,
            _viewportSize.height,
          );
          final visible = renderer.index.query(view);
          if (visible.isNotEmpty) {
            await measure('visibleCommitRebuild', () {
              renderer.synchronize(
                renderer.scene.translated(
                  renderer.scene.paintOrder[visible.first].node.id,
                  Point2(.25, 0),
                ),
              );
              _scene = renderer.scene;
            });
          }
          _coldSamples.clear();
          _coldStart = SchedulerBinding
              .instance
              .currentSystemFrameTimeStamp
              .inMicroseconds;
          _coldEnd = null;
          final evictBefore = Map<String, Object?>.of(renderer.tileStatistics!);
          final returnCamera = _camera;
          final evictClock = Stopwatch()..start();
          for (final zoom in [.25, .5, 1.0, 2.0, 4.0, 8.0, 1.01]) {
            _setCamera(
              _camera.zoomAt(
                Point2(_viewportSize.width / 2, _viewportSize.height / 2),
                zoom,
              ),
            );
            await prepareViewport();
          }
          // Empty views still occupy raster slots. Visit enough distinct views
          // to force eviction on both native and browser viewport sizes.
          for (var i = 0; i < 16; i++) {
            _setCamera(_camera.pan(Point2(-4000, 0)));
            await prepareViewport();
          }
          final restoreClock = Stopwatch()..start();
          _setCamera(returnCamera);
          await prepareViewport();
          await WidgetsBinding.instance.endOfFrame;
          final restoreWallMs = restoreClock.elapsedMicroseconds / 1000;
          final evictWallMs = evictClock.elapsedMicroseconds / 1000;
          _coldEnd = SchedulerBinding
              .instance
              .currentSystemFrameTimeStamp
              .inMicroseconds;
          await Future<void>.delayed(const Duration(seconds: 1));
          debugPrint(
            'PHASE0_DIAGNOSTIC ${jsonEncode({
              'kind': 'coldWallAudit',
              'zoomNormalizedBeforeOpen': true,
              'lifecycleChanges': _lifecycleChanges - lifecycleBefore,
              'viewportChanged': initialViewport != _viewportSize,
              'scene': distribution.name,
              'session': session,
              'mode': kProfileMode ? 'profile' : 'debug',
              'recovery': _recovery,
              'viewport': {'width': _viewportSize.width, 'height': _viewportSize.height, 'dpr': pixelRatio},
              'openToCacheAndFrameworkPaintMs': openWall,
              'openingFrames': openingFrames,
              'operations': operations,
              'evictSweepAndReturnWallMs': evictWallMs,
              'returnToEvictedViewMs': restoreWallMs,
              'evictBefore': evictBefore,
              'evictionFrames': _coldSamples.toJson(),
              'oldRendererDisposed': old?.isDisposed,
              'oldImagesAfterDispose': old?.ownedImageHandles,
              'oldParagraphsAfterDispose': old?.ownedParagraphs,
              'textLayouts': renderer.textLayoutCount,
              'tiles': renderer.tileStatistics,
              'load': _loads[distribution.name],
            })}',
          );
        }
      }
      debugPrint(
        'PHASE0_SUITE_DONE ${jsonEncode({'runs': 0, 'purpose': 'coldWallAudit'})}',
      );
    } catch (error, stack) {
      debugPrint('PHASE0_SUITE_FAILED $error\n$stack');
    } finally {
      if (mounted) setState(() => _suiteActive = false);
    }
  }

  Future<void> _runPhase02() async {
    setState(() {
      _suiteActive = true;
    });
    var runs = 0;
    try {
      if (_phase03) {
        for (final (distribution, workload) in [
          (SceneDistribution.normal, 'editSingle'),
          (SceneDistribution.dense, 'editSingle'),
          (SceneDistribution.dense, 'editMulti'),
          if (_interleaved) (SceneDistribution.dense, 'editInterleaved'),
          (SceneDistribution.dense, 'editOffscreen'),
        ]) {
          await _load(distribution);
          if (!mounted || !await _ready!.future) return;
          _resetCamera();
          await _startRun(workload: workload, seconds: 6);
          runs++;
        }
        for (var i = 0; i < 3; i++) {
          await _load(
            i == 1 ? SceneDistribution.normal : SceneDistribution.dense,
          );
          if (!mounted || !await _ready!.future) return;
          _resetCamera();
          if (i == 1) {
            final text = _renderer!.scene.paintOrder.firstWhere(
              (e) => e.node.content is TextContent,
            );
            _setCamera(
              Camera(
                translation: Point2(
                  _viewportSize.width / 2 - text.worldBounds.center.x,
                  _viewportSize.height / 2 - text.worldBounds.center.y,
                ),
              ),
            );
          }
          // Fresh renderer: include initial cache population, no warmup.
          await _startRun(
            workload: i == 1 ? 'coldTextArea' : 'reopen',
            seconds: 3,
          );
          runs++;
          if (i == 0) {
            _setCamera(
              _camera.zoomAt(
                Point2(_viewportSize.width / 2, _viewportSize.height / 2),
                1.01,
              ),
            );
            await _startRun(workload: 'coldZoom', seconds: 3);
            runs++;
          }
        }
      }
      final cases = <(SceneDistribution, String)>[
        (SceneDistribution.sparse, 'camera'),
        (SceneDistribution.normal, 'normalEditing'),
        (SceneDistribution.dense, 'camera'),
        (SceneDistribution.dense, 'zoomIn'),
        (SceneDistribution.dense, 'zoomOut'),
        (SceneDistribution.dense, 'overview'),
        (SceneDistribution.dense, 'oscillation'),
        (SceneDistribution.dense, 'staticRedraw'),
        (SceneDistribution.dense, 'movement'),
        (SceneDistribution.imageHeavy, 'camera'),
        (SceneDistribution.deepHierarchy, 'camera'),
      ];
      for (final (distribution, workload) in cases) {
        if (distribution != _distribution) await _load(distribution);
        if (!mounted || !await _ready!.future) return;
        _resetCamera();
        _hitProbe = _probeHits();
        final report = await _startRun(workload: workload, warmup: true);
        if (!mounted || report['cancelled'] == true) return;
        runs++;
      }
      await _load(SceneDistribution.dense);
      if (!mounted || !await _ready!.future) return;
      await _runDiagnostics();
      if (!mounted) return;
      final soakClock = Stopwatch()..start();
      var ticks = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        ticks++;
        final renderer = _renderer!;
        if (_phase03) {
          _applyEdits(['element-0'], ticks.isEven ? .25 : -.25);
        } else {
          final next = renderer.scene.translated(
            'element-0',
            Point2(ticks.isEven ? .25 : -.25, 0),
          );
          renderer.synchronize(next);
          _scene = next;
        }
        if (ticks % 20 == 0 || ticks == 1) {
          debugPrint(
            'PHASE0_DIAGNOSTIC ${jsonEncode({'kind': 'stressMemory', 'cycle': ticks, 'elapsedSeconds': soakClock.elapsedMilliseconds / 1000, 'tiles': renderer.tileStatistics, 'overviewBytes': renderer.overviewBytes, 'textLayouts': renderer.textLayoutCount})}',
          );
        }
      });
      try {
        _resetCamera();
        await _startRun(
          workload: 'stress',
          warmup: true,
          seconds: _soakSeconds,
        );
        runs++;
      } finally {
        timer.cancel();
      }
      debugPrint(
        'PHASE0_DIAGNOSTIC ${jsonEncode({'kind': 'stressEnd', 'seconds': soakClock.elapsedMilliseconds / 1000, 'commits': ticks, 'tiles': _renderer!.tileStatistics})}',
      );
      debugPrint('PHASE0_SUITE_DONE ${jsonEncode({'runs': runs})}');
    } catch (error, stack) {
      debugPrint('PHASE0_SUITE_FAILED $error\n$stack');
    } finally {
      if (mounted) {
        setState(() {
          _suiteActive = false;
        });
      }
    }
  }

  void _applyEdits(List<String> ids, double dx) {
    final renderer = _renderer!;
    final total = Stopwatch()..start();
    final geometry = Stopwatch()..start();
    final current = renderer.scene;
    final next = ids.length == 1
        ? current.translated(ids.single, Point2(dx, 0))
        : current.transformed({
            for (final id in ids)
              id:
                  Transform2.translation(dx, 0) *
                  current.paintOrder[current.paintIndex(id)!].node.transform,
          });
    final geometryMicros = geometry.elapsedMicroseconds;
    final sync = Stopwatch()..start();
    renderer.synchronize(next);
    final syncMicros = sync.elapsedMicroseconds;
    _scene = next;
    if (_recording && _commitSeries.length < 12000) {
      _telemetry.commit.add(total.elapsedMicroseconds);
      _commitSeries.add([
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
        total.elapsedMicroseconds,
        geometryMicros,
        syncMicros,
        renderer.lastIndexUpdateMicros,
        renderer.lastCacheInvalidationMicros,
        renderer.lastValidationMicros,
        next.delta?.resolvedCount ?? 0,
        renderer.lastSynchronizedEntries,
      ]);
    }
  }

  Future<void> _runDiagnostics() async {
    final renderer = _renderer!;
    BenchmarkScene current = _scene!;
    final full = TimingSamples();
    final incremental = TimingSamples();
    final geometry = TimingSamples();
    final synchronization = TimingSamples();
    final index = TimingSamples();
    // Same element, alternating world delta, synchronous end-to-end CPU cost.
    for (final legacy in [true, false]) {
      for (var i = 0; i < 272; i++) {
        final delta = Point2(i.isEven ? 0.25 : -0.25, 0);
        final totalClock = Stopwatch()..start();
        final geometryClock = Stopwatch()..start();
        BenchmarkScene next;
        if (legacy) {
          final resolved = current.paintOrder.first;
          final node = resolved.node;
          final parent = resolved.worldTransform * node.transform.inverse();
          final transform =
              (Transform2.translation(delta.x, delta.y) *
                      resolved.worldTransform)
                  .relativeTo(parent);
          next = BenchmarkScene([
            for (final n in current.nodes)
              n.id == node.id ? n.withTransform(transform) : n,
          ]);
        } else {
          next = current.translated(current.paintOrder.first.node.id, delta);
        }
        final geometryMicros = geometryClock.elapsedMicroseconds;
        final syncClock = Stopwatch()..start();
        renderer.synchronize(next);
        final syncMicros = syncClock.elapsedMicroseconds;
        current = next;
        if (i >= 16) {
          (legacy ? full : incremental).add(totalClock.elapsedMicroseconds);
          if (!legacy) {
            geometry.add(geometryMicros);
            synchronization.add(syncMicros);
            index.add(renderer.lastIndexUpdateMicros);
          }
        }
      }
    }
    _scene = current;
    debugPrint(
      'PHASE0_DIAGNOSTIC ${jsonEncode({'kind': 'repeatedCommits', 'fullReconstructionReference': full.toJson(), 'incrementalTotal': incremental.toJson(), 'incrementalGeometry': geometry.toJson(), 'incrementalSynchronization': synchronization.toJson(), 'incrementalIndex': index.toJson(), 'lastResolved': current.delta?.resolvedCount, 'lastSynchronized': renderer.lastSynchronizedEntries})}',
    );
    if (renderer.tileStatistics != null) {
      final view = _camera.worldViewport(
        _viewportSize.width,
        _viewportSize.height,
      );
      final scale = _camera.zoom * MediaQuery.devicePixelRatioOf(context);
      await renderer.prepareTiles(view, scale);
      if (!mounted) return;
      final candidates = renderer.index.query(view);
      if (candidates.isNotEmpty) {
        final id = renderer.scene.paintOrder[candidates.first].node.id;
        final before = Map<String, Object?>.of(renderer.tileStatistics!);
        final clock = Stopwatch()..start();
        renderer.synchronize(renderer.scene.translated(id, Point2(.25, 0)));
        _scene = renderer.scene;
        final commitMicros = clock.elapsedMicroseconds;
        final invalidated = renderer.tileStatistics!['invalidations'] as int;
        await renderer.prepareTiles(view, scale);
        debugPrint(
          'PHASE0_DIAGNOSTIC ${jsonEncode({'kind': 'partialTileRebuild', 'synchronousCommitMs': commitMicros / 1000, 'commitAndRasterReadyWallMs': clock.elapsedMicroseconds / 1000, 'invalidatedTiles': invalidated - (before['invalidations'] as int), 'builtTiles': (renderer.tileStatistics!['builds'] as int) - (before['builds'] as int), 'before': before, 'after': renderer.tileStatistics})}',
        );
      }
    }
    if (_optimized &&
        !_tiles &&
        !_retainedExperiment &&
        !_retained &&
        !_layers) {
      final rebuild = Stopwatch()..start();
      await renderer.prepareOverview();
      debugPrint(
        'PHASE0_DIAGNOSTIC ${jsonEncode({'kind': 'deferredOverviewRebuild', 'wallMs': rebuild.elapsedMicroseconds / 1000, 'overviewBytes': renderer.overviewBytes})}',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final before = _telemetry.paintCount;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    debugPrint(
      'PHASE0_DIAGNOSTIC ${jsonEncode({'kind': 'idle', 'seconds': 2, 'paintCallbacks': _telemetry.paintCount - before})}',
    );
    for (var i = 0; i < 16; i++) {
      final fixture = BenchmarkFixture.generate(
        i.isEven ? SceneDistribution.dense : SceneDistribution.imageHeavy,
      );
      final temporary = await SceneRenderer.create(
        fixture.scene,
        imageSide: i.isEven ? 1024 : 2048,
        cacheOverview: _optimized && !_retainedExperiment,
        cacheTiles: _tiles && !_retainedExperiment,
        recoverTiles: _recovery,
        repairTiles: _dirtyRepair,
        retainRanges: _retained,
        retainLayers: _layers,
      );
      if (temporary.tileStatistics != null) {
        await temporary.prepareTiles(Bounds2(0, 0, 800, 600), 1);
      }
      final allocated = temporary.imageBytes + temporary.overviewBytes;
      // Exercise cache invalidation and both static preview display lists.
      final recorder = ui.PictureRecorder();
      temporary.paint(
        ui.Canvas(recorder),
        temporary.index.query(Bounds2(0, 0, 800, 600)),
        movingIndex: 0,
        moveDelta: Point2(1, 0),
        optimized: _optimized,
      );
      recorder.endRecording().dispose();
      temporary.synchronize(
        temporary.scene.translated('element-0', Point2(1, 0)),
      );
      if (temporary.tileStatistics != null) {
        await temporary.prepareTiles(Bounds2(0, 0, 800, 600), 1);
      } else if (_optimized && !_retainedExperiment && !_retained && !_layers) {
        await temporary.prepareOverview();
      }
      final retainedBeforeDispose = temporary.retainedStatistics;
      final layersBeforeDispose = temporary.layerStatistics;
      temporary.dispose();
      debugPrint(
        'PHASE0_DIAGNOSTIC ${jsonEncode({'kind': 'openClose', 'cycle': i, 'allocatedLogicalPixelBytes': allocated, 'overviewBytesAfterDispose': temporary.overviewBytes, 'imageHandlesAfterDispose': temporary.ownedImageHandles, 'paragraphsAfterDispose': temporary.ownedParagraphs, 'tilesAfterDispose': temporary.tileStatistics, if (_retainedExperiment) 'retainedBeforeDispose': retainedBeforeDispose, if (_retainedExperiment) 'retainedAfterDispose': temporary.retainedStatistics, if (_layers) 'layersBeforeDispose': layersBeforeDispose, if (_layers) 'layersAfterDispose': temporary.layerStatistics, 'disposed': temporary.isDisposed})}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }
  }

  void _markPointer(PointerEvent event) {
    _telemetry.markPointer(event.timeStamp);
    _inputReportTimer?.cancel();
    _inputReportTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_suiteActive) {
        debugPrint(
          'PHASE0_DIAGNOSTIC ${jsonEncode({'kind': 'pointer', 'metrics': _telemetry.toJson()})}',
        );
      }
    });
  }

  void _cancelMove() {
    _movePointer = null;
    _movingIndex = null;
    _moveStartWorld = null;
    _moveDelta.value = Point2.zero;
  }

  void _beginMove(PointerDownEvent event) {
    _markPointer(event);
    if (!_moveMode || _recording || event.buttons != kPrimaryButton) return;
    if (_movePointer != null) {
      setState(_cancelMove);
      return;
    }
    final point = _camera.viewportToWorld(
      Point2(event.localPosition.dx, event.localPosition.dy),
    );
    final id = _renderer?.hitTest(
      point,
      worldTolerance: _camera.worldTolerance(6),
    );
    setState(() {
      _selected = id;
      if (id == null) return;
      _movePointer = event.pointer;
      _moveStartWorld = point;
      _movingIndex = _renderer!.scene.paintIndex(id);
    });
  }

  void _updateMove(PointerMoveEvent event) {
    _markPointer(event);
    if (event.pointer != _movePointer || _moveStartWorld == null) return;
    _telemetry.markUpdate();
    _moveDelta.value =
        _camera.viewportToWorld(
          Point2(event.localPosition.dx, event.localPosition.dy),
        ) -
        _moveStartWorld!;
  }

  void _commitMove() {
    final index = _movingIndex;
    if (index == null || _renderer == null) return;
    final renderer = _renderer!;
    final clock = Stopwatch()..start();
    try {
      final next = _scene!.translated(
        renderer.scene.paintOrder[index].node.id,
        _moveDelta.value,
      );
      renderer.synchronize(next);
      _scene = next;
      _overviewTimer?.cancel();
      if (_optimized &&
          !_suiteActive &&
          !_retainedExperiment &&
          !_retained &&
          !_layers) {
        _overviewTimer = Timer(const Duration(milliseconds: 300), () async {
          final revision = renderer.revision;
          try {
            if (_tiles) return;
            await renderer.prepareOverview();
            if (mounted &&
                identical(renderer, _renderer) &&
                renderer.revision == revision &&
                renderer.overviewBytes == 0) {
              if (_tiles) return;
              await renderer.prepareOverview();
            }
          } catch (error) {
            if (mounted && identical(renderer, _renderer)) {
              _result = 'Overview cache unavailable: $error';
            }
          }
          if (mounted && identical(renderer, _renderer)) setState(() {});
        });
      }
      if (_telemetry.recording) {
        _telemetry.commit.add(clock.elapsedMicroseconds);
      }
    } catch (error) {
      _result = 'Movement cancelled: $error';
    }
    _cancelMove();
  }

  @override
  void didChangeViewFocus(ui.ViewFocusEvent event) {
    _viewFocused = event.state == ui.ViewFocusState.focused;
    _focusChanges++;
    if (!_viewFocused! && _movePointer != null) setState(_cancelMove);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleChanges++;
    if (state != AppLifecycleState.resumed && _movePointer != null) {
      setState(_cancelMove);
    }
  }

  void _select(TapUpDetails details) {
    final camera = _camera;
    final point = camera.viewportToWorld(
      Point2(details.localPosition.dx, details.localPosition.dy),
    );
    setState(() {
      _selected = _renderer?.hitTest(
        point,
        worldTolerance: camera.worldTolerance(6),
      );
    });
  }

  @override
  void dispose() {
    _generation++;
    _overviewTimer?.cancel();
    _inputReportTimer?.cancel();
    _startupTimer?.cancel();
    _cancelRun();
    WidgetsBinding.instance.removeObserver(this);
    if (_ready?.isCompleted == false) _ready!.complete(false);
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _sweep.dispose();
    _transformation.dispose();
    _moveDelta.dispose();
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    final fixture = _fixture;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(title: const Text('Whiteboard · Rendering spike')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (compact)
                    DropdownButton<SceneDistribution>(
                      value: _distribution,
                      items: [
                        for (final distribution in SceneDistribution.values)
                          DropdownMenuItem(
                            value: distribution,
                            child: Text(distribution.label),
                          ),
                      ],
                      onChanged: _loading || _recording || _suiteActive
                          ? null
                          : (distribution) {
                              if (distribution != null) _load(distribution);
                            },
                    )
                  else
                    for (final distribution in SceneDistribution.values)
                      ChoiceChip(
                        label: Text(distribution.label),
                        selected: distribution == _distribution,
                        onSelected: _loading || _recording || _suiteActive
                            ? null
                            : (_) => _load(distribution),
                      ),
                  if (compact)
                    IconButton(
                      tooltip: 'Reset camera',
                      onPressed: renderer == null || _recording
                          ? null
                          : _resetCamera,
                      icon: const Icon(Icons.center_focus_strong),
                    )
                  else
                    OutlinedButton(
                      onPressed: renderer == null || _recording
                          ? null
                          : _resetCamera,
                      child: const Text('Reset camera'),
                    ),
                  OutlinedButton(
                    onPressed: renderer == null || _recording || _suiteActive
                        ? null
                        : () => setState(() {
                            _cancelMove();
                            _moveMode = !_moveMode;
                          }),
                    child: Text(_moveMode ? 'Select / move' : 'Pan mode'),
                  ),
                  FilledButton(
                    onPressed: renderer == null || _recording || _suiteActive
                        ? null
                        : () => _startRun(),
                    child: Text(_recording ? 'Recording…' : 'Run 10 s sweep'),
                  ),
                  if (!compact)
                    TextButton(
                      onPressed: renderer == null || _recording || _suiteActive
                          ? null
                          : _runSuite,
                      child: const Text('Run Phase 0 suite'),
                    ),
                  if (_recording)
                    TextButton(
                      onPressed: () => setState(() {
                        _cancelRun();
                        _result = 'Run cancelled.';
                      }),
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ),
            if (renderer != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  compact
                      ? '10,000 drawable elements · ${fixture!.scene.nodes.length - 10000} groups\n100 image refs · 4 originals · ${(renderer.imageBytes / (1024 * 1024)).toStringAsFixed(0)} MiB decoded'
                      : '10,000 drawable elements · ${fixture!.scene.nodes.length - 10000} groups · '
                            '100 image references / 4 synthetic originals · ${(renderer.imageBytes / (1024 * 1024)).toStringAsFixed(0)} MiB decoded pixels',
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                compact
                    ? 'Drag/pinch to navigate · tap to inspect. Synthetic lab; no saves.'
                    : 'Drag to pan · pinch or scroll to zoom · tap to hit-test. Synthetic lab; no editing or local saves.',
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(
                            onPressed: () => _load(_distribution),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _viewportSize = constraints.biggest;
                        return Focus(
                          autofocus: true,
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.escape) {
                              setState(_cancelMove);
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Semantics(
                            label:
                                'Benchmark canvas. Drag to pan, pinch to zoom, tap to inspect an element.',
                            child: Listener(
                              onPointerSignal: _markPointer,
                              onPointerPanZoomUpdate: _markPointer,
                              onPointerDown: _beginMove,
                              onPointerMove: _updateMove,
                              onPointerUp: (event) {
                                if (event.pointer == _movePointer) {
                                  setState(_commitMove);
                                }
                              },
                              onPointerCancel: (event) {
                                if (event.pointer == _movePointer) {
                                  setState(_cancelMove);
                                }
                              },
                              child: GestureDetector(
                                onTapUp: _recording || _moveMode
                                    ? null
                                    : _select,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    RepaintBoundary(
                                      child: IgnorePointer(
                                        child: ValueListenableBuilder<Matrix4>(
                                          valueListenable: _transformation,
                                          builder: (context, _, _) {
                                            final camera = _camera;
                                            final painter = BenchmarkPainter(
                                              renderer: renderer!,
                                              optimized: _optimized,
                                              devicePixelRatio:
                                                  MediaQuery.devicePixelRatioOf(
                                                    context,
                                                  ),
                                              viewport: camera.worldViewport(
                                                _viewportSize.width,
                                                _viewportSize.height,
                                              ),
                                              zoom: camera.zoom,
                                              selected: _selected,
                                              movingIndex: _movingIndex,
                                              moveDelta: _moveDelta,
                                              telemetry: _telemetry,
                                              includeText:
                                                  !_recording ||
                                                  _workload != 'withoutText',
                                              includeImages:
                                                  !_recording ||
                                                  _workload != 'withoutImages',
                                            );
                                            return _layers
                                                ? BenchmarkLayerCanvas(
                                                    painter: painter,
                                                  )
                                                : CustomPaint(painter: painter);
                                          },
                                        ),
                                      ),
                                    ),
                                    InteractiveViewer(
                                      transformationController: _transformation,
                                      boundaryMargin: const EdgeInsets.all(
                                        double.infinity,
                                      ),
                                      minScale: Camera.minZoom,
                                      maxScale: Camera.maxZoom,
                                      panEnabled: !_recording && !_moveMode,
                                      scaleEnabled: !_recording && !_moveMode,
                                      child: const SizedBox.expand(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                [
                  if (_selected != null) 'Hit: $_selected',
                  ?_result,
                  if (kDebugMode)
                    compact
                        ? 'Debug timings only. Measure in profile mode.'
                        : 'Debug build: timings are diagnostic only. Use profile mode for measurements.',
                  if (!kDebugMode && _result == null)
                    'Run a sweep to collect frame timings. Device acceptance budgets remain unverified.',
                ].join('\n'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
