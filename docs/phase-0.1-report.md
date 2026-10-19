# Phase 0.1 — Rendering remediation and foundation recovery

Follow-up: [Phase 0.2 zoom/cache experiment and current decision](phase-0.2-report.md). Historical Phase 0.1 measurements are preserved below.

Report date: 16 October 2026, Africa/Cairo. Measurements began 15 October. Requirements: approved Whiteboard V1 blueprint and Phase 0.1 remediation request. This report supersedes the acceptance assessment in [Phase 0](phase-0-report.md); historical data remains intact.

## Decision and Phase 1 prerequisite verification

**NO-GO. Original Phase 0 acceptance gates are not satisfied.** Dense continuous navigation improved substantially, but P95 remains above 16.7 ms on both measured targets. Physical input-to-presentation latency and long-term memory stability are unvalidated. The latest Phase 1 request explicitly says to stop when a critical foundation blocker remains; Phase 1 implementation therefore did not begin. Phases 1–5 remain unimplemented and blocked.

The synchronous single-leaf update bottleneck is fixed. Geometry and renderer synchronization touch one affected leaf without rebuilding the full scene. Overview regeneration remains expensive and is measured separately. This is a useful remediation, not approval of the complete production architecture or a 60 FPS claim.

## Audit and confirmed root causes

The audit covered the existing scene resolver, camera, geometry, grid, hit testing, painter, text/path preparation, lifecycle, tests, original report and raw benchmark files.

1. The original dense failure was reproduced: new uncached reference P95 182.802 ms native and 146.100 ms Chrome, consistent with historical 184.465 / 144.200 ms. This is a rendering failure, not a network or download failure.
2. Dense native reference build P95 8.683 ms versus raster 182.802 ms identifies a raster-stage bottleneck. Chrome reports 55.400 ms build / 146.100 ms raster. Culling correctly reaches all 10,000 visible leaves and cannot remove visible overlapping content.
3. Paragraphs, layouts, paths and matrices were already cached per render entry. Recreating paragraphs on every paint was not the root cause. Native dense text entry preparation totaled 63.885 ms once in the reference load, not each frame. Text omission reduces reference navigation P95 to 27.829 ms native / 48.600 ms web; image omission leaves 185.507 / 146.000 ms. These diagnostic omissions retain logical scene resources and do not constitute an approved fidelity policy.
4. A small committed move previously reconstructed resolved geometry for every node; renderer synchronization scanned every paint entry. Both now use an affected-entry delta.
5. Static visible content is still redrawn during selection movement. Query candidate sets/lists and sorting allocate during navigation. The bounded overview removes most recording/raster work at minified scales, exposing query sorting as a larger CPU share.
6. The reported stale `MyApp` test mismatch was not present at audit time: `main.dart` contained the original counter again. The counter test was preserved and a real `BenchmarkApp` startup/disposal test added. The final suite is green without removing functionality.

### Profile evidence and limits

Native engine timelines establish **Skia/Metal** through `GrMtlPipelineStateBuilder` and raster events. A roughly 12-second reference trace window contains 224 `Rasterizer::DrawToSurfaces` intervals with P95 181.928 ms, versus `LayerTree::Paint` 4.859 ms. The candidate capture window contains 295 raster intervals with P95 3.085 ms; that window emphasizes cached zoom-out and must not replace the complete sweep P95 of 29.471 ms. Shader-finalization intervals in the reference window have P95 1.141 ms (21 observations); they do not alone explain a 182 ms frame.

Dart CPU sampling at 1000 microseconds collected 535 reference samples in the dense window; allocation/TLAB work had 54 self ticks and `_paintDirect` 198 inclusive ticks. Candidate sampling collected 1220 samples; comparisons and quicksort dominate the active Dart sample list. Sample proportions across different frame counts/work are not absolute CPU cost or exact allocation counts.

Separate Chrome CPU/cc/gpu trace windows ran for about three seconds at dense zoom-out. Reference CPU samples include CanvasKit Wasm functions and `_paintDirect`; the candidate capture is mostly idle/program with list sorting among active functions. Browser GPU command-buffer/compositor events are present. These are CPU/engine timelines, not GPU hardware counters or display scanout measurements. The after diagnostic used Chrome 155.0.8059.82 after the installed browser updated; primary before/after frame suites both used **155.0.8059.40**. Diagnostic frame rows are excluded from the acceptance comparison.

## Retained implementation, ownership and scope

Pure Dart immutable benchmark scene data remains authoritative. ID maps, hierarchy adjacency and node-aligned world transforms allow a transform batch to resolve affected descendants in parent-first order. Lists use immutable 128-entry chunks, copying touched chunks and their shallow directory. Unrelated resolved records are shared. Deltas carry an opaque identity token rather than retaining a chain of old scenes. This is a minimal transform-only scene contract, not the Phase 1 document model, commands or history. Parent updates remain proportional to affected descendants; directory copying is not constant-space at arbitrary scene size.

Renderer synchronization consumes a delta only when its base identity matches the current snapshot. It validates all affected content/index ranges before publishing; unrelated snapshots use a validated full-scan fallback. Structural or content changes still require renderer replacement. No production revision queue or stale-command protocol is claimed.

One composited overview raster preserves paint order, text and images for compact scenes. It is capped at 2048×2048 pixels / **16 MiB logical RGBA**; worlds wider/taller than 8192 units skip it. It is used only at or below its stored pixel resolution. Zooming closer restores full vector/paragraph drawing. Geometry, spatial selection and hit testing remain authoritative. This is raster reuse without text/geometry omission; font-quality equivalence at every fractional zoom/DPR is not exhaustively validated.

Each renderer owns cached paths, paragraphs, original images and its overview. Concurrent overview requests share one pending build; generation checks dispose stale results after mutation or disposal. A commit invalidates the overview; manual rebuild is debounced by 300 ms while direct drawing remains available. At most one overview build is in flight per renderer; the 16 MiB cap covers the published raster only, not temporary picture/texture/upload memory or overlapping sessions.

The page session owns current scene, camera, selection/preview, timers, telemetry and async load generation. It cancels deferred work and removes frame callbacks/observers at disposal. A two-picture static-preview candidate was evaluated and removed after unreliable/regressed exploratory results; a later uncached run also varied, so no isolated causal performance claim is made. Moving content uses the original live drawing path with correct paint order.

No package, SDK, state-management, dependency-injection, schema, migration or Android/iOS/platform runner change was made. Flutter SDK rendering/testing APIs and existing lints are sufficient. Collectors use Python standard library and an existing Node/Playwright installation; no pub/npm dependency was installed. `main.dart` and its counter behavior remain intact.

## Environment and benchmark method

Apple M4, 10 logical CPUs, 16 GiB, arm64, macOS 26.5.1 (25F80). Flutter 3.41.9 stable / Dart 3.11.5; framework `00b0c91f06`, engine revision `42d3d75a56efe1a2e9902f52dc8006099c45d937`. Exact provenance is in [environment.json](../benchmark_results/phase01/environment.json).

- Native: profile build, Skia/Metal, 800×600 logical window, DPR 1; camera canvas 800×346, movement 800×326. Native primary comparisons both enable 1 ms Dart CPU sampling and default VM timeline streams, with overhead included. The window was raised during a ten-second startup delay. No viewport/lifecycle changes occurred. This native backend emitted no view-focus events; null focus state is not proof of foreground status throughout.
- Web: JavaScript profile build, CanvasKit, hardware ANGLE Metal / Apple M4, Chrome 155.0.8059.40, fresh isolated headless process per variant, 1200×796 DPR 1; camera canvas 1200×582, movement 1200×562. Primary runs have tracing/CPU profiling disabled. Node 24.19.0 / Playwright 1.62.1. Application Wasm mode was not runtime-benchmarked; CanvasKit Wasm samples do not imply Dart Wasm execution.
- Fixed seed `0x5eed`, 10,000 leaves: 5000 shapes, 2500 24-point freehand/highlighter strokes, 2000 text/sticky notes, 400 arrows, 100 image references. Sparse spans 100,000×100,000; dense/image-heavy 1600×900; hierarchy adds 64 structural groups. The continuous sweep reaches 10,000 visible leaves in all dense variants. Four generated originals are 1024×1024 normally, 2048×2048 image-heavy: 16 / 64 MiB logical source RGBA. Image-heavy display bounds are 1500×1100. This is not 100 unique photos or codec/import testing.
- One-second warmup, ten-second camera / five-second movement windows, one-second timing drain. Camera sweeps approximately 0.223–4.482×; fixed overview holds 0.22313× while panning. 32 hit-query warmups plus 256 timed probes. Commit diagnostics use 16 warmups plus 256 timed alternating leaf moves per strategy. Sixteen open/close renderer cycles alternate dense/image-heavy.
- Nearest-rank percentiles; series capacity 2400, no primary frame series reaches that limit. Counts below are actual delivered engine timings. `stage = max(build,raster)` per frame, not total frame span, throughput/FPS or physical input-to-display latency. Custom stopwatch query/record/commit timing is reported separately. Browser timer zeros mean below timer resolution.
- Single primary suite per variant/target, fixed order, normal OS variability; no confidence intervals, thermal control or approved release baseline devices. Native and web viewport sizes differ. All performance claims use profile builds, never correctness-test debug timings.

## Before/after actual frame timings

All times ms. Format P50 / P95 / P99. N is before→after engine frame count. Raw build/raster/total-span series are preserved in each JSON.

| Target | Scene/workload | N | Reference stage | Retained stage |
| --- | --- | --- | --- | --- |
| macos | sparse / camera | 600→600 | 1.652 / 2.639 / 3.013 | 1.611 / 2.567 / 3.199 |
| macos | sparse / movement | 300→300 | 0.978 / 1.224 / 1.333 | 1.004 / 1.214 / 1.306 |
| macos | dense / camera | 202→486 | 26.562 / 182.802 / 205.826 | 3.053 / 29.471 / 53.293 |
| macos | dense / movement | 299→300 | 9.277 / 10.391 / 12.583 | 9.497 / 10.735 / 11.765 |
| macos | imageHeavy / camera | 165→381 | 33.777 / 196.101 / 207.566 | 2.944 / 53.390 / 154.427 |
| macos | imageHeavy / movement | 267→263 | 18.548 / 19.466 / 21.946 | 18.783 / 20.280 / 21.363 |
| macos | deepHierarchy / camera | 165→452 | 36.429 / 205.748 / 218.491 | 3.031 / 38.046 / 55.578 |
| macos | deepHierarchy / movement | 301→300 | 10.128 / 10.709 / 11.202 | 10.149 / 10.871 / 11.285 |
| macos | dense / withoutText | 494→495 | 16.826 / 27.829 / 33.224 | 17.161 / 27.194 / 31.674 |
| macos | dense / withoutImages | 207→202 | 26.021 / 185.507 / 200.409 | 26.260 / 187.674 / 201.738 |
| macos | dense / overview | 201→600 | 49.247 / 51.634 / 54.940 | 3.134 / 3.419 / 3.865 |
| web | sparse / camera | 600→601 | 1.500 / 2.599 / 3.200 | 1.100 / 2.899 / 3.399 |
| web | sparse / movement | 299→296 | 1.500 / 1.801 / 2.100 | 1.799 / 2.100 / 2.400 |
| web | dense / camera | 119→417 | 48.699 / 146.100 / 158.401 | 3.799 / 48.799 / 56.100 |
| web | dense / movement | 183→189 | 15.400 / 16.400 / 16.799 | 14.801 / 15.600 / 15.900 |
| web | imageHeavy / camera | 118→339 | 48.199 / 148.100 / 158.500 | 4.000 / 50.900 / 147.100 |
| web | imageHeavy / movement | 178→183 | 15.900 / 17.000 / 17.601 | 15.400 / 16.200 / 17.399 |
| web | deepHierarchy / camera | 105→404 | 60.400 / 148.900 / 159.800 | 3.901 / 59.100 / 70.599 |
| web | deepHierarchy / movement | 155→159 | 18.201 / 19.000 / 19.500 | 17.400 / 18.300 / 18.701 |
| web | dense / withoutText | 242→246 | 28.400 / 48.600 / 49.500 | 27.901 / 47.599 / 48.901 |
| web | dense / withoutImages | 119→121 | 48.101 / 146.000 / 158.400 | 47.700 / 141.600 / 158.599 |
| web | dense / overview | 99→601 | 54.500 / 56.100 / 59.900 | 3.701 / 5.099 / 6.000 |

Dense navigation P95 is reduced by 83.9% native and 66.6% web, yet still fails 16.7 ms. Fixed overviews pass the provisional stage target, but zoom-in vector fallback and image-heavy movement remain bottlenecks. Omission probes intentionally bypass the overview and do not represent candidate rendering with all content.

### Frame versus custom CPU timings

Dense camera P95 values, ms:

| Target/variant | Build | Raster | Total span | Query CPU | Paint-record CPU | Synthetic update→paint |
| --- | --- | --- | --- | --- | --- | --- |
| macos/before | 8.683 | 182.802 | 363.029 | 1.921 | 6.499 | 8.457 |
| macos/after | 3.186 | 29.471 | 52.841 | 2.952 | 1.008 | 3.023 |
| web/before | 55.400 | 146.100 | 199.400 | 1.600 | 46.900 | 48.601 |
| web/after | 8.799 | 48.799 | 53.299 | 3.300 | 6.599 | 7.199 |

Query CPU rises in the cached sweep because far more zoomed-out frames are delivered and each still collects/sorts visible candidates. Different frame-weighted visibility distributions prevent interpreting this as a same-input per-query regression. Dense hit-test P95 after remediation is 0.064 ms native / 0.201 ms web (256 probes; candidate P95 93 / 91). These bounded probes do not prove pathological overlapping-hit behavior.

### Preparation and first viewport

Dense reference→candidate renderer preparation: 92.616→408.721 ms native and 112.400→424.600 ms web. Candidate overview preparation within those loads: 309.690 / 309.000 ms, raster 7,879,832 logical bytes. Native candidate per-type entry preparation: shapes 0.479 ms, strokes 8.067 ms, text 65.038 ms, arrows 0.286 ms, images 0.006 ms; original image generation 17.703 ms. Web text preparation 70.403 ms, original images 27.701 ms. These are summed preparation timers, not per-frame costs.

Candidate initial sparse Dart-entry→framework-interactive viewport: 159.043 ms native / 406.299 ms web. Collector launch→ready: 1039.132 ms native; navigation→ready 1071.000 ms web. Dense load→framework-interactive: 496.660 / 491.400 ms. These warm synthetic startup diagnostics are below ~3 s; they exclude physical scanout, cold offline bootstrap, real project deserialization and fonts/assets import.

## Incremental update measurements

Timed synchronous work includes new scene resolution, renderer synchronization, index updates and overview invalidation. Geometry/synchronization/index components are nested, not additive. All 256 final moves resolve and synchronize exactly one leaf.

| Target | Strategy | P50 ms | P95 ms | P99 ms |
| --- | --- | --- | --- | --- |
| macos | fullReconstructionReference | 10.408 | 12.769 | 17.207 |
| macos | incrementalTotal | 0.004 | 0.005 | 0.007 |
| macos | incrementalGeometry | 0.002 | 0.003 | 0.005 |
| macos | incrementalSynchronization | 0.001 | 0.001 | 0.001 |
| macos | incrementalIndex | 0.001 | 0.001 | 0.001 |
| web | fullReconstructionReference | 11.000 | 13.000 | 21.900 |
| web | incrementalTotal | 0.000 | 0.100 | 0.101 |
| web | incrementalGeometry | 0.000 | 0.100 | 0.101 |
| web | incrementalSynchronization | 0.000 | 0.000 | 0.100 |
| web | incrementalIndex | 0.000 | 0.000 | 0.100 |

**Deferred overview rebuild is additional work:** 158.892 ms native / 133.799 ms web in one post-burst observation, not a P95. Its 300 ms debounce delay is also excluded from synchronous commit timings. Cache regeneration is global and must be improved before production editing. This benchmark compares the current full constructor/full-sync reference with incremental updates, not a byte-identical replay of the historical Phase 0 resolver. Reference executes first, so sequence/JIT/GC bias remains. Timer resolution especially limits the web microbenchmarks.

## Memory, idle and resource lifecycle

Sixteen cycles per primary suite create fresh dense/image-heavy renderers, paint a movement preview, update a leaf, invalidate/rebuild an overview when enabled, and dispose. Instrumented owned image/paragraph handle counts are zero after each disposal. These are app-owned handle counters, not proof that GPU allocations have returned to the OS.

- Native process RSS at 1 Hz: peak **756.3→778.5 MiB** reference→candidate; final 746.1→696.3 MiB. These separate processes do not establish the exact incremental texture cost. RSS includes VM/engine caches; sampling can miss peaks and excludes driver/other-process allocations.
- Forced-GC native Dart heap checkpoints after cycle 0/3/7/11/15: candidate **26,659,936→26,660,064 bytes**, then unchanged. Reference 26,636,032→26,636,160, then unchanged. The 128-byte bounded increase supports no accumulating Dart scene chain in this short run. It does not establish long-running GPU or native leak freedom.
- Approximate browser JS heap peak **388.0→436.2 MiB**. Candidate cycle 0→15 rises 130.8→436.2 MiB without a forced-GC checkpoint. After the separate software input probe it drops to about 76.5 MiB. GC behavior is visible, but retained browser heap stability is **unproven**; no browser heap-snapshot retention analysis or GPU accounting was completed. JS heap is not total browser/CanvasKit/GPU memory and cannot be compared directly with native RSS.
- Both candidate two-second settled-idle checks recorded **zero canvas paint callbacks**. This does not mean zero engine/compositor frames or zero idle power.
- Engine-reported layer/picture cache byte counters are zero on these backends and do not measure application overview/source textures.

Concurrent request coalescing, old-revision cache rejection and disposal during in-flight image generation are covered by automated regressions. Long soak duration, memory pressure, actual editor-session mount/unmount with imported assets and mobile GPU budgets remain untested.

## Input findings

Chrome software probe performs 120 drag steps and 24 wheel events after frame benchmarking; canvas-only pixel checks change for both pan and zoom. Pointer receipt→end of paint recording uses one local monotonic Stopwatch; platform timestamps are checked only for ordering, never subtracted across epochs. No timestamp regressions were observed.

Final cumulative 143 observed samples: reference P50/P95/P99 **47.500 / 49.300 / 60.401 ms**, candidate **1.701 / 9.600 / 26.600 ms**. Drag-only candidate P95 2.500 ms (119 samples). These are sequence-dependent software scheduling diagnostics, not physical latency or 143 independent end-to-end trials. They exclude hardware, OS/browser dispatch before Flutter receipt, rasterization, presentation and scanout. **The ≤33 ms physical input gate remains unmeasured.** Physical mouse/trackpad, stylus, multi-touch and high-speed capture were unavailable for this pass.

## Correctness and validation actually executed

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: **36 passed** on the host runner.
- `flutter test --no-pub --platform chrome`: **36 passed**, including raster, cache lifecycle and incremental geometry regressions.
- Profile macOS reference/candidate builds: succeeded; both primary suites completed all 11 workloads and diagnostics with no collector RPC errors.
- Profile web reference/candidate builds: succeeded; both primary suites completed all 11 workloads and diagnostics with no browser application errors. Viewport/lifecycle disturbance flags are clear. Primary browser version/backend match.
- Native/browser diagnostic CPU/engine traces were actually captured. Bounded web diagnostic stops after three workloads and correctly records `complete:false`, `diagnosticComplete:true`; it is not a completed full benchmark suite.
- Original geometry/camera/index/raster regressions retained: affine inversion, hierarchy/cycle/orphan rules, sub-1× 2D scale, world ±1e9, topmost rotated hit tests, culling equivalence, highlighter alpha and image resource reuse.
- Added: 1000 alternating leaf updates with immutable snapshot/identity sharing; 100 parent/child transform batches against full resolution; cache bounds/compositing/large-origin/fallback/invalidation; live movement paint order; atomic invalid batch rollback; stale branch fallback; coalesced async generation and stale/disposed result rejection; actual benchmark entry-point smoke test.

Android SDK/Java and Xcode are installed, but no connected Android device was available and iOS simulator discovery previously stalled. Windows requires another host. No Android/iOS/Windows/Safari/Edge runtime or performance result is claimed. These are platform availability/validation gaps, not application compilation failures.

No measured debug test duration is used as production performance evidence. See README for reproduction. Final formatting validation passed across all 20 Dart source/test files. Python collectors compiled, the Node collector passed its syntax check, and `git diff --check` passed. The summary tool validated 22 matched workload pairs (44 primary workload observations); a separate check verified final application source hashes, compressed trace references, all 64 open/close cycles and primary completion/backend/configuration flags.

### Failure classification and exclusions

No package download or network failure explains the measured slow frames. Existing dependencies were used with `--no-pub`. SDK cache writes needed the execution environment's authorization; they succeeded. Native desktop CPU profiling initially ignored command-line arguments; explicit installed-engine environment switches fixed this, and primary artifacts confirm 1000 microsecond samples.

An MCP browser transport closed while exporting a full-session trace; recovered aggregates are retained as exploratory, not a compilation/application failure. A cached headless shell selected SwiftShader and a different browser version; that run is excluded from the hardware comparison. One separate after-diagnostic attempt received localhost `ERR_CONNECTION_REFUSED` because the local server had ended; restarting the server allowed the diagnostic to complete. This is collector setup, not an app/network service defect.

Uncontrolled native visibility inspections and an exploratory preview cache had large variability. All are retained under explicit exploratory filenames, excluded from primary claims. Raw CPU/timeline artifacts are losslessly gzipped; JSON aggregate references point to them. Original Phase 0 artifacts are unchanged. Final application hashes identify the retained source; native reference predates optimized-only pending-cache guards and extra diagnostic logging, with the uncached rendering path unchanged.

## Files created or modified in this remediation

The repository already contained the Phase 0 files, many untracked; this list identifies remediation changes rather than attributing all untracked foundation files to this pass.

| File | Change |
| --- | --- |
| `lib/src/benchmarks/benchmark_scene.dart` | Affected-subtree transforms, ID lookup, immutable chunked snapshots and identity-bound deltas. |
| `lib/src/benchmarks/scene_renderer.dart` | Validated incremental synchronization, bounded overview, profiling/preparation counters and async disposal guards. |
| `lib/src/benchmarks/benchmark_canvas.dart` | Optimized painting option and overview-use telemetry; existing selection/culling retained. |
| `lib/src/benchmarks/benchmark_page.dart` | Diagnostic workloads, cache rebuild scheduling, pointer/focus instrumentation and timer lifecycle. |
| `lib/src/benchmarks/benchmark_telemetry.dart` | Bounded pointer scheduling/timestamp/overview counters. |
| `test/widget_test.dart` | Preserve counter test; add actual benchmark startup/disposal smoke coverage. |
| `test/incremental_scene_test.dart` (new) | Immutable incremental and hierarchical batch equivalence regressions. |
| `test/render_cache_test.dart` (new) | Raster reuse, stale async, atomic synchronization and disposal regressions. |
| `tool/run_native_benchmark.py` | Own-process RSS, VM CPU/timeline/forced-GC capture and bounded cleanup. |
| `tool/start_web_benchmark.js` | Shared browser-resident diagnostic collection. |
| `tool/run_web_benchmark.mjs` (new) | Isolated hardware-checked browser collection, optional short profiling/input probes. |
| `tool/summarize_phase01.py` (new) | Validate and summarize the 22 primary frame workloads and diagnostics. |
| `benchmark_results/phase01/` (new) | Four primary aggregates, input/environment files, separate traces, explicitly excluded exploratory artifacts and summary/provenance. |
| `README.md` | Reproduction, ownership and measurement boundaries. |
| `docs/phase-0-report.md` | Link to remediation; preserve historical results. |
| `docs/phase-0.1-report.md` (new) | This assessment and exact phase gate. |

## Architecture decisions and minimum next work

Retain pure Dart affine geometry, authoritative immutable snapshots, affected-entry synchronization, origin rebasing, rebuildable grid and generation-checked resources. Keep the bounded overview as an experimentally validated minification optimization. Do not finalize global raster regeneration or the full-vector zoom-in path as the production solution.

Before Phase 1, the next focused rendering iteration should:

1. Remove high-zoom/overlap spikes and global cache-rebuild stalls. Evaluate bounded tiles or zoom-specific retained chunks with partial invalidation and explicit temporary-memory limits. Benchmark movement and cache invalidation as well as static navigation. This is proposed work, not implemented or guaranteed to pass.
2. If testing indicates full-detail stress cannot meet the target, submit a concrete fidelity/LOD policy for approval with visual comparisons. No element/text omission or weaker acceptance budget is approved by this report.
3. Repeat equivalent profile suites on agreed baseline hardware, including required mobile/Windows targets; add controlled repetitions and review timing-drain completeness. Native/browser differences here are not platform rankings.
4. Measure real input-to-presentation latency and complete a longer memory/pressure soak with retained browser/native/GPU accounting. Expand fractional-zoom/DPR cache visual coverage.
5. Reassess the unchanged gates before starting the document/commands engine.

Rendering P95 ≤16.7 ms: **FAIL** for required dense continuous navigation. Physical input P95 ≤33 ms: **UNMEASURED**. Long-running memory stability: **UNPROVEN**. Warm synthetic first framework viewport ~≤3 s: **observed**, broader startup scenarios unvalidated. Correctness/static checks: **PASS** for the available host and Chrome suites. No storage, advanced tools, PNG export or Phase 1–5 functionality was started. No user commands, package installation, migration or platform configuration change is required to preserve the current app. Manual follow-up should focus on actual trackpad/touch cancellation, fractional zoom fidelity and device memory pressure.
