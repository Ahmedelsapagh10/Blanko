# Phase 0 — Project Foundation & Rendering Feasibility

Follow-up: [Phase 0.1 remediation and current acceptance decision](phase-0.1-report.md). Historical Phase 0 measurements below are preserved.

Date: 15 October 2026 (Africa/Cairo). Source of requirements: the approved Whiteboard V1 Production Implementation Blueprint.

## 1. Recommendation and phase boundary

**NO-GO for advancing to feature implementation.** The correctness foundation is reusable, but the current scene renderer fails the provisional P95 16.7 ms rendering budget in dense navigation on both measured targets. Sparse success does not establish 10K dense-scene feasibility.

Phase 0 implementation and its assessment are complete. Storage, production drawing tools, project serialization, advanced editing, PNG export, backend, and collaboration have not been started. This report recommends a further rendering-performance iteration; it does not approve or begin the next phase.

All performance tables below come from the corrected profile builds. Early runs exposed a 2D/Z-axis zoom adapter defect and were superseded. Final dense, image-heavy, and hierarchical camera runs each reached **10,000 simultaneously visible drawable elements**. Every final run reports unchanged viewport size and zero lifecycle changes.

## 2. Project and environment assessment

The existing project was a Flutter starter with platform folders already present. The previous rendering spike was extended rather than replacing the app or initializing another project. The original `lib/main.dart`, starter test, package versions, and Android/iOS/native runner configuration are preserved.

- Hardware: Apple M4, 10 logical CPUs, 16 GiB RAM, arm64; macOS 26.5.1 (25F80).
- Flutter 3.41.9 stable, Dart 3.11.5; framework revision `00b0c91f06`. Both profile builds succeeded with the installed SDK and locked dependencies, using `--no-pub`.
- Native measurement: macOS profile app, 800×600 logical window, DPR 1; canvas 800×346 for camera runs and 800×326 for movement runs. SDK-default native rendering backend; its exact backend was not independently instrumented.
- Browser measurement: Chromium 155.0.8059.40, Flutter JavaScript profile build with CanvasKit, 1200×796 window, DPR 1; camera canvas 1200×582, movement canvas 1200×562. CDP reports hardware WebGL/GPU compositing via ANGLE Metal on Apple M4. Application Wasm mode was not benchmarked; the build's Wasm dry run is not a runtime result.
- Xcode 26.2 (17C52), macOS/iOS SDKs 26.2 are installed. `simctl` is a first-launch wrapper which attempted CoreSimulator setup and stalled; this task's diagnostic processes were terminated. `flutter doctor -v` therefore did not complete. iOS runtime, physical-device provisioning, and signing remain unverified.
- Android SDK platforms 31/33/34/35/36, build tools, ADB 36.0.0, and OpenJDK 21.0.7 were found. `adb devices -l` returned no connected devices. Android build/profile validation was not performed; tool presence alone is not a working-device claim.
- Windows native builds require a Windows host, which is unavailable here. Safari is installed but was not benchmarked; Edge was not found in `/Applications`. No Firefox compatibility claim is made.

These are available-host feasibility measurements, not results from approved release baseline devices. Targets ran sequentially after compilation, with normal OS/background variability and warm filesystem/browser caches. Viewport sizes differ, so native/web numbers are not a platform-efficiency comparison.

## 3. Architecture, ownership, and packages

The minimal foundation follows the modular monolith direction without adding state-management, persistence, or rendering packages.

- **Pure Dart scene/geometry:** immutable typed shape, stroke, text/sticky, arrow, image-reference, and group data; stable IDs; parent validation; iterative hierarchy resolution; affine transforms including shear. Children resolve into ordered world-space render records. This is a feasibility scene contract, not the complete portable document schema.
- **Session owner:** `BenchmarkPage` owns the current immutable scene, camera adapter, selection, transient pointer/drag preview, animation, timers, readiness/run completers, telemetry, and async job generation. Committing a drag creates a new scene; cancelling leaves the source scene unchanged.
- **Camera:** a pure Dart camera maps world/viewport coordinates and anchors zoom. `InteractiveViewer` is retained as the gesture adapter. A viewport-sized painter renders independently of the transformed gesture child. The 2D adapter reads X/Y scale, independently of matrix Z scale.
- **Renderer:** cached paths, text layouts, matrices and four synthetic image resources are owned by `SceneRenderer`. It consumes scene snapshots; synchronizing a committed snapshot refreshes transform/index caches. It does not modify scene data. Renderer replacement/disposal releases text and image handles. Late image preparation is rejected by the session generation and disposed.
- **Spatial index:** a uniform grid is a dependency-free candidate, with bounded per-entry cell membership and a scan fallback for broad queries. It is rebuildable and not a source of document truth. Committed transforms update affected entries; camera and preview motion do not rebuild it.
- **Hot path:** camera updates rebuild only the canvas subtree; preview changes notify the painter through a `ValueNotifier`. No widget per scene element and no app-wide state emission per pointer movement. The current painter still redraws static visible elements during a move, which is a performance limitation.
- **Lifecycle:** pointer cancellation, Escape, tool-mode changes, inactive application state, scene replacement and disposal cancel transient movement. Timings callbacks/observers are unregistered, animation/controllers/notifiers/timers are disposed or cancelled, and stale async results cannot replace the active scene.

**Packages:** only existing Flutter SDK APIs, `flutter_test`, and `flutter_lints` are used. Existing `cupertino_icons` is preserved. No new pub/npm dependency, SDK upgrade, migration, or platform configuration was introduced. Python collection uses the standard library; the web collector runs inside an existing Playwright tool/session.

### Evidence-driven camera revisions

An actual raster regression rendered a small rectangle correctly near the origin but lost it at world coordinate 1,000,000,000. Painting now subtracts the camera origin in Dart doubles **before** matrices reach the engine's float representation. The raster regression passes on native and Chrome, alongside world/local transform tests.

A widget regression also demonstrated the separate 2D scale contract: a matrix with X/Y scale 0.25 and Z scale 1 must produce 4× world viewport width. Reading the largest 3D axis incorrectly treated that zoom as 1. Corrected profile coverage counters now reach all 10K elements.

## 4. Benchmark design and measurement meaning

Every distribution contains exactly 5,000 shapes, 2,500 freehand/highlighter polylines (24 points each), 2,000 multiline text/sticky notes, 400 arrows and 100 image references. Seed: `0x5eed`, fixed integer generator. Categories are interleaved in paint order. Sparse positions span 100,000×100,000 world units; dense/image-heavy positions span 1,600×900. The hierarchy variant adds 64 structural groups above 10,000 drawable leaves.

Four deterministic raster originals are generated through Flutter's canvas: **1024×1024** each normally, **2048×2048** each for image-heavy. Image-heavy display bounds are 1500×1100 world units. Logical RGBA pixel accounting is 16 MiB/64 MiB respectively, excluding copies, GPU caches, paths, text, engine and application memory. This does not test photographic codec/import behavior or 100 unique decoded assets.

- Each camera run configures one second warmup plus ten seconds continuous pan/zoom; each movement run configures one second warmup plus five seconds preview and one commit. Completion occurs on an available frame. Camera sweep zoom is approximately 0.223×–4.482× with viewport-proportional pan. The supported camera limits 0.02×–32× are tested separately.
- Engine `FrameTiming` records build, raster, total frame span and `max(build,raster)`. **Stage** in the tables means that slower stage, not total span or physical input latency. Percentiles use nearest rank. Series retain at most 2,400 samples; actual counts are shown. A one-second callback-drain interval follows each run; traces would be needed to audit exceptionally late timings.
- Query and paint-recording CPU durations use stopwatches. Instrumentation has overhead and is included. Paint CPU is recording work, not a GPU hardware timer.
- The update-to-paint proxy begins at a synthetic controller update and ends when the painter finishes recording. It excludes input hardware, OS/browser dispatch, raster/presentation and display scanout. It cannot establish the Blueprint's P95 ≤33 ms input-latency gate.
- Hit probes use 32 warmup queries followed by 256 timed queries, alternating deterministic element centers with viewport positions. Timer-quantized zero values mean below resolution, not zero cost. Adversarial worst-case hit paths are not exhaustively tested.
- Movement selects a known leaf for reproducibility, so selection CPU is measured by the separate hit probes. The commit column is **one observation per scene**, not a statistically meaningful commit P95. A full-scene immutable resolve is currently performed at commit; only changed spatial entries are updated.
- Diagnostic dense probes omit drawing text or images while retaining the original scene, resources and culling. They are sequence-dependent single runs, not proof of a GPU-level cause or memory savings.
- There is no dedicated no-motion idle-frame benchmark or allocation/GPU trace. Idle/repaint behavior is assessed by code inspection and interaction tests.

## 5. Measured profile results

All times are milliseconds. Raw aggregates, sample counts, startup timings, validity flags and memory observations are in `benchmark_results/macos-profile.json` and `benchmark_results/web-profile.json`.

### Continuous camera motion


| Target | Scene | Frames | Stage P50 | Stage P95 | Build P95 | Raster P95 | Total-span P95 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| macOS | Sparse | 600 | 1.924 | 3.147 | 0.905 | 3.147 | 4.582 |
| macOS | Dense | 200 | 26.619 | 184.465 | 8.322 | 184.465 | 362.619 |
| macOS | Image-heavy | 168 | 32.889 | 190.803 | 8.759 | 190.803 | 371.939 |
| macOS | 64-level hierarchy | 170 | 35.550 | 200.750 | 8.528 | 200.750 | 390.529 |
| Chromium | Sparse | 600 | 2.600 | 3.200 | 3.200 | 2.000 | 4.900 |
| Chromium | Dense | 121 | 46.600 | 144.200 | 54.100 | 144.200 | 196.200 |
| Chromium | Image-heavy | 121 | 47.600 | 140.600 | 57.000 | 140.600 | 196.100 |
| Chromium | 64-level hierarchy | 102 | 62.200 | 150.100 | 55.700 | 150.100 | 199.500 |


### Selection movement preview and commit


| Target | Scene | Frames | Stage P50 | Stage P95 | Update→paint proxy P95 | Single commit |
| --- | --- | --- | --- | --- | --- | --- |
| macOS | Sparse | 300 | 1.052 | 1.289 | 0.223 | 23.050 |
| macOS | Dense | 301 | 8.621 | 8.840 | 1.833 | 6.308 |
| macOS | Image-heavy | 279 | 17.765 | 19.142 | 2.613 | 6.745 |
| macOS | 64-level hierarchy | 300 | 9.671 | 10.003 | 2.104 | 6.374 |
| Chromium | Sparse | 298 | 1.900 | 2.200 | 1.100 | 29.300 |
| Chromium | Dense | 182 | 15.300 | 16.100 | 14.300 | 8.600 |
| Chromium | Image-heavy | 176 | 16.200 | 17.100 | 15.200 | 10.000 |
| Chromium | 64-level hierarchy | 157 | 17.900 | 18.500 | 16.500 | 9.900 |


### CPU and visibility observations during camera motion


| Target | Scene | Query CPU P95 | Paint CPU P95 | Hit CPU P95 | Hit candidates P95 | Max visible |
| --- | --- | --- | --- | --- | --- | --- |
| macOS | Sparse | 0.071 | 0.108 | 0.003 | 1 | 7 |
| macOS | Dense | 1.960 | 6.056 | 0.056 | 93 | 10000 |
| macOS | Image-heavy | 2.039 | 6.384 | 0.059 | 156 | 10000 |
| macOS | 64-level hierarchy | 1.916 | 6.347 | 0.063 | 112 | 10000 |
| Chromium | Sparse | 0.200 | 0.500 | 0.000 | 1 | 11 |
| Chromium | Dense | 1.500 | 45.900 | 0.200 | 91 | 10000 |
| Chromium | Image-heavy | 1.700 | 48.200 | 0.200 | 156 | 10000 |
| Chromium | 64-level hierarchy | 1.500 | 46.900 | 0.200 | 112 | 10000 |


### Dense drawing-omission probes


| Target | Omitted draw content | Frames | Stage P95 |
| --- | --- | --- | --- |
| macOS | withoutText | 501 | 26.494 |
| macOS | withoutImages | 213 | 182.116 |
| Chromium | withoutText | 244 | 48.200 |
| Chromium | withoutImages | 120 | 144.400 |


### Startup and memory

- macOS: 168.53 ms from Dart entry to the correctly positioned framework viewport; 736.49 ms from native process launch to receipt of its ready log. The latter is an upper-bound diagnostic including collector/log delivery, not display scanout.
- Chromium: 280.80 ms from Dart entry to framework viewport; 555.80 ms from navigation to the ready log intercepted in the page. Browser caches were warm; cold offline bootstrap was not measured.
- Native process RSS sampled at 1 Hz peaked at **764.5 MiB**. Sampling can miss shorter peaks and excludes memory attributed to other processes/driver components. This is not a measured Dart heap or full GPU footprint.
- Browser post-run JavaScript heap snapshots peaked at approximately **156.1 MiB** (`performance.memory`). This is a nonstandard, approximate browser metric; it is not total browser, Wasm, GPU or application memory. It is not comparable with native RSS.
- These single suites do not establish leak freedom, a stable long-term memory ceiling, or safe mobile budgets.

## 6. Bottlenecks and validation findings

**Measured:** dense camera motion is dominated by the reported raster stage. macOS dense build P95 is 8.322 ms while raster P95 is 184.465 ms; Chromium dense build P95 is 54.100 ms and raster P95 is 144.200 ms. The grid is not the dominant total cost in those runs. At low zoom, culling correctly retains all 10K visible leaves, so it cannot solve dense overdraw by itself.

**Measured diagnostic:** omitting text drawing reduces dense stage P95 from 184.465 to 26.494 ms on macOS, and from 144.200 to 48.200 ms in Chromium. Image omission does not produce a comparable improvement in the dense fixture. Text rasterization/cache behavior and overlapping drawing are therefore priorities for profiling; shader compilation, GPU cache churn and fill-rate causes are hypotheses, not established findings. Image-heavy and deep-hierarchy results also depend on geometry/overlap and test sequence; the hierarchy is flattened before painting, so its timings do not prove recursive traversal is the issue.

**Code inspection and measurements:** moving one selection still redraws the static visible scene. Every spatial query creates a candidate set/list and sorts its results. Commit reconstructs scene resolution for all nodes; one native sparse commit took 23.050 ms even though its spatial update is small. No exact allocation counts were measured. Those costs justify targeted caching/invalidation and incremental-resolution experiments before features expand.

**Correctness verified:** affine inversion/composition, preserving world transforms under parent changes/movement, hierarchy uniqueness/cycle/orphan rules, ordering, incremental index equivalence with rebuilds, camera round trips, sub-1x adapter scale, rotation-aware hit testing, preview-versus-commit semantics, pointer/Escape cancellation, disposal during async load, highlighter self-intersection opacity, real image-resource reuse, and large-coordinate raster placement. The Dart coordinate tests span ±1e9 with an explicit tolerance; the raster regression covers origins 0, 1e6 and 1e9. Arbitrary magnitudes and all geometries are not thereby validated.

Synthetic browser wheel zoom-in, zoom-out and mouse drag each changed canvas-only pixels. Real trackpad, stylus, multi-touch and physical end-to-end latency remain untested. Parent groups are tested as structural transforms; group/frame editing is absent.

## 7. Tests and commands actually executed

- `flutter test --no-pub`: **29 passed** on the native host test runner. These are correctness tests, not macOS profile measurements.
- `flutter test --no-pub --platform chrome`: **29 passed**, including the raster and 2D camera adapter regressions. Debug test timings are excluded from every performance table.
- Targeted renderer/page regressions were rerun while fixing failures. After the additional Escape cancellation assertion, `test/benchmark_page_test.dart` passed all **3 tests on the native host and 3 in Chrome**.
- `flutter analyze --no-pub`: no issues. Formatting verification: no changes required.
- Native and web profile builds with `PHASE0_AUTORUN=true`: succeeded. Each final profile suite completed **10 runs**; final validity flags show no viewport/lifecycle disturbance and no web collector errors.
- Native Python collector compiled and ran successfully. Web Playwright collector was executed successfully. `git diff --check` passed.
- `flutter --version`, Xcode SDK/version checks, bounded Android SDK/ADB/JDK checks were executed. Doctor/simulator discovery did not complete; they are not marked passed.

Reproduce with the commands in `README.md`. To run automatic suites:

```sh
flutter build macos --no-pub --profile --dart-define=PHASE0_AUTORUN=true -t lib/benchmark_main.dart
python3 tool/run_native_benchmark.py --timeout 240
flutter build web --no-pub --profile --no-web-resources-cdn --dart-define=PHASE0_AUTORUN=true -t lib/benchmark_main.dart
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

After the native collector has exited, execute `tool/start_web_benchmark.js` in an existing Playwright session, wait for `window.__phase0.complete`, and save that object with its environment details. Do not run builds/tests/another rendering target during measurements. The native collector closes only its own app; the web server should be stopped after collection.

## 8. Known limitations and acceptance status

- **Rendering P95 gate: failed in dense/overlapping navigation on measured targets.** Sparse success and responsive hit probes do not override it.
- **Input-to-display P95 ≤33 ms: unmeasured.** The synthetic proxy cannot pass this gate. Real-device touch/trackpad/IME validation remains outside this spike.
- **Memory/no-growth gate: unproven.** Only a short sequence, coarse RSS sampling, and approximate JS heap snapshots are available. No mobile memory budget, pressure test or GPU resource accounting was validated.
- **First viewport:** measured framework-ready diagnostics are below the provisional ~3 s target for these fixtures/caches, but cold browser bootstrap, fonts/offline operation, real project loading and scanout are unproven.
- One suite per target, fixed order, single omission probes and one commit per scene do not establish repeatability or statistically robust worst-case guarantees. Extremely late timing callbacks beyond the drain window can be missed.
- Candidate index coordinate range, local geometry limits, text fallback/fonts, arbitrary affine skew hit tolerance, worst-case overlapping hit tests and enormous-world rendering need broader production contracts/testing.
- Fixture image generation does not validate import codecs, staging, lazy decode, eviction, real-photo workloads, 100 unique originals or portable asset handling. Embedded licensed font strategy remains undecided.
- Native and web viewport sizes/timing implementations differ. No Windows, Safari, Edge, Android or iOS runtime/performance claim is made.
- The scene model has no production serializer/version migration, full payload-security validator, asset/font manifest, undo history, group/frame editing, durable save or exporter. They were intentionally excluded from Phase 0.

## 9. Architecture decisions requiring revision and exact next work

Retain the pure Dart affine geometry, immutable source scene, generation-checked lifecycle, cached render resources, viewport-relative drawing, and the grid as a candidate. Do not finalize the current redraw strategy for the full product.

The recommended next approved work is a **Phase 0 rendering-performance iteration**, before any storage or production-tool phase:

1. Agree baseline devices, display scaling and repeatable viewport/workload definitions. Capture Dart/GPU timelines for dense camera motion, text omitted and image-heavy cases in fresh processes and after scene changes; audit timing-drain completeness.
2. Compare bounded picture/chunk caching and static/dynamic paint separation using this same dataset and visual checks. Measure cache invalidation and memory cost; evaluate level of detail for tiny text/strokes only where evidence and fidelity permit it. A lower-level RenderObject alone should not be assumed to fix a raster-dominated workload.
3. Remove full-scene resolution from a single committed move where measurements justify it; benchmark repeated commits and index maintenance, rather than inferring a percentile from one observation.
4. Add repeated scene-open/close/move/navigation stress runs with heap/GPU accounting and pressure tests. Confirm real mouse/trackpad/touch input-to-presentation latency and large-world behavior on actual target devices.
5. Repeat profile runs until agreed rendering, input and memory gates pass, then request approval to enter the document/commands and interaction implementation phase described by the Blueprint.

No next-phase implementation was begun. Review and explicit approval are required before that work.

## 10. Files created or modified

Paths are relative to the project root. This is the completed Phase 0 foundation, including the retained initial spike.


| File | Responsibility/change |
| --- | --- |
| lib/benchmark_main.dart | Separate lab entry point; startup clock; default app preserved. |
| lib/src/geometry/geometry.dart | Pure Dart points/bounds/affine transforms, inverse validation and scale calculation. |
| lib/src/viewport/camera.dart | Retained pure Dart world/viewport mapping, pan, anchored/clamped zoom. |
| lib/src/benchmarks/benchmark_scene.dart | Typed immutable hierarchy and completed world-space movement. |
| lib/src/benchmarks/benchmark_fixtures.dart | Retained deterministic mixed distributions, depth and asset-reference definitions. |
| lib/src/spatial/spatial_grid.dart | Candidate culling index, safe query ranges and committed-entry updates. |
| lib/src/benchmarks/scene_renderer.dart | Cached rendering, origin rebasing, hit testing, transform synchronization and resource disposal. |
| lib/src/benchmarks/benchmark_canvas.dart | New viewport-sized painter, preview culling and stage instrumentation. |
| lib/src/benchmarks/benchmark_telemetry.dart | New bounded query/recording/update/commit metrics owned by the session. |
| lib/src/benchmarks/frame_samples.dart | Separate bounded build/raster/stage/total-span series and percentiles. |
| lib/src/benchmarks/benchmark_page.dart | Session lifecycle, pan/zoom adapter, selection/movement and automatic suite orchestration. |
| test/geometry_camera_test.dart | Numerical/transform/camera invariants including large-world coordinates. |
| test/benchmark_scene_test.dart | Hierarchy, world-preserving movement, fixture mix and metric-series tests. |
| test/spatial_grid_test.dart | Culling equivalence and incremental updates versus rebuilds, including overflow cases. |
| test/scene_renderer_test.dart | Native/web raster, resource, highlighter, precision and hit-test regressions. |
| test/benchmark_page_test.dart | Pan/zoom adapter, movement commit/cancel/Escape, responsive load and disposal regressions. |
| tool/run_native_benchmark.py | New bounded native runner, own-process RSS sampling, cleanup and JSON collection. |
| tool/start_web_benchmark.js | New browser-resident Playwright collector and environment query. |
| benchmark_results/macos-profile.json | Final measured native aggregates, readiness records and RSS samples. |
| benchmark_results/web-profile.json | Final measured web aggregates, readiness records and approximate JS heap snapshots. |
| benchmark_results/environment.json | Hardware/toolchain facts, method, source hashes and input-smoke outcomes. |
| README.md | Usage, repeatable collection commands, ownership and measurement definitions. |
| docs/phase-0-report.md | This engineering report and phase recommendation. |


No package/SDK version, database migration, Android/iOS entitlement, Gradle, CocoaPods or platform runner changes were required.
