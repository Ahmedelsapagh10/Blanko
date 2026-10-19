Follow-up: [Phase 0.3 sustained-update and cold-cache validation](phase-0.3-report.md). Historical measurements below are unchanged.

# Phase 0.2 — Zoom rendering, cache stability and performance validation

Date: 16 October 2026, Africa/Cairo. Scope: the approved Phase 0.2 remediation brief and existing Whiteboard blueprint. [Phase 0.1](phase-0.1-report.md) remains the historical reference.

## 1. Decision

**NO-GO for Phase 1.** The tile experiment removes most warm zoom-threshold raster spikes and substantially reduces P95 in short dense workloads. It does not provide consistently smooth navigation: cold-cache creation has large tail stalls, and the sustained-update workload still exceeds the unchanged 16.7 ms target. Primary results include all delivered stress samples; no fast-tail-only percentile is substituted.

The candidate is implemented and tested behind **`PHASE02_TILES=true`**, with the existing Phase 0.1 path as the default. It is not promoted to the production rendering policy. Physical input and long-term/device memory requirements are untested, not observed failures. Native collection limits are distinguished below. No Phase 1 features or subsequent phase began.

## 2. Confirmed causes and optimization rationale

### Zoom representation transitions

The old composited overview is valid only up to its stored scale (1× in this dense fixture). Crossing that threshold restores thousands of full-detail drawing operations. Paragraph construction/layout and paths already occur during render-entry preparation, not camera motion. Text/content/style/local-width changes are rejected by the transform-only synchronization contract; changing them requires renderer replacement. Zoom therefore does not rebuild text layouts or local paths.

New Chrome reference oscillation around 1× reaches P95 **134.500 ms**; fixed-camera forced redraw is **4.601 ms**. The oscillation telemetry records 264 overview paints; other paints use direct drawing. This supports a scale/representation raster bottleneck, not per-frame paragraph reconstruction. Precise glyph-atlas/driver mechanisms remain hypotheses without hardware GPU counters.

**Experiment:** retain spatial raster tiles at fixed power-of-two scales. Expected benefit: reuse unchanged composited content across pan/zoom and keep both adjacent buckets available near a threshold. Trade-offs: texture memory, cold-build latency, scale-bucket eviction and offscreen raster contention. Validation: matched profile sweeps, threshold oscillation, CPU/engine timings, full frame intervals, cache counters and pixel/geometry regressions.

### Whole-scene invalidation

Phase 0.1 invalidates its entire overview on any committed transform. The new reference post-burst overview rebuild takes **135.900 ms** in one observation. The candidate invalidates only tiles intersecting the old/new world bounds plus a one-pixel raster gutter, including affected pending work. Unrelated resident images survive. A regression proves unrelated pending content also survives; a revision change affecting the actual pending tile discards its late result.

The first prototype used a global pending-job generation and dropped a completed image if the camera had moved away. These unnecessary discards were corrected. The prototype recorded zero discarded jobs in this particular workload, so those correctness/reuse fixes are **not claimed as a measured cause of its earlier slow frames**.

Expected benefit is local regeneration rather than a global rebuild. Cost is checking at most 63 resident keys plus one pending key per transform; a parent update still depends on affected descendants. Fixed-count synchronous commit tests and separately measured async rebuilds assess both parts.

### Cold cache work remains expensive

An asynchronous image build can still contend with foreground rendering. One in-flight job limits concurrency and memory; it does not impose a wall-time or raster-work budget. On a miss the live vector renderer remains available, so new tile rasterization and direct drawing can be expensive together. The short dense run delivers fewer engine timing records than the reference despite a much lower P95 stage duration. P99 and frame-interval data expose these stalls. This experiment is not a 60 FPS result.

Spatial query sets/sorting remain in the paint path. Historical Phase 0.1 CPU traces identified sorting/allocation as a larger Dart share after caching; no speculative index rewrite was added here.

## 3. Cache design, correctness and lifecycle

- Each `SceneRenderer` optionally owns one `SceneTileCache`; immutable scene/geometry and the spatial index remain authoritative. No second document model exists.
- A tile has a 512×512 interior plus a one-pixel gutter on each side: **514×514 / 1,056,784 logical RGBA bytes**. The published cache cap is **67,108,864 bytes (64 MiB)**, allowing 63 such images. One additional image can be in flight; temporary pictures, uploads, original images and driver caches are outside that cap.
- Keys are world cell X/Y and a power-of-two pixel-scale bucket derived from zoom×DPR. The selected scale is at least the requested scale. Unsupported pixel scales above 256 or viewport requests exceeding the cache budget use live drawing. Empty tiles also consume this bounded cache; sparse-scene allocation is an identified efficiency limitation.
- Adjacent zoom buckets remain resident subject to LRU eviction. Camera movement does not invalidate existing content. Completed unchanged off-view work can remain cached when it will not evict the currently required set. The cache has no unbounded infinite-canvas allocation.
- Tiles composite all intersecting elements in source paint order. There is no text omission, geometry simplification or lower-resolution interim placeholder. Higher-resolution tiles are used when needed; misses use full-detail vector/paragraph drawing. Selection/hit testing use original geometry.
- Tile recording rebases world coordinates in Dart doubles before engine transforms. Gutter clipping prevents painting translucent tile borders twice. RTL/seam pixel checks, large origins, precision, hit testing and culling regressions pass; exhaustive fractional-scale/DPR/font visual goldens are still untested.
- Cache jobs coalesce, reject affected stale results and dispose late images after close. Resident images and notifiers are released on disposal. Engine `toImage` work cannot be cancelled once submitted; context-loss/non-resolving-driver recovery is unvalidated.
- Active element movement bypasses the baked static raster to preserve correct paint order. Static selection overlay painting can reuse tiles. A two-second settled idle check is separate from deliberate per-tick static redraw. Full production static/dynamic layer separation is not implemented.

## 4. Reproducible environment and measurement meanings

Apple M4, 10 logical CPUs, 16 GiB, arm64, macOS 26.5.1 (25F80). Installed Flutter **3.41.9 stable**, Dart **3.11.5**, framework `00b0c91f06`, engine revision `42d3d75a56efe1a2e9902f52dc8006099c45d937`. No upgrades or package changes. Exact hashes/configuration are in [environment.json](../benchmark_results/phase02/environment.json).

Primary Chrome comparisons both use **155.0.8059.82**, hardware ANGLE Metal / Apple M4, JavaScript profile build with CanvasKit, fresh isolated headless processes, 1200×796 DPR 1, camera canvas 1200×582 and movement canvas 1200×562. CPU tracing is disabled for primary suites. Node 24.19.0 / existing Playwright 1.62.1 collect results. Application Dart Wasm was not runtime-tested; a successful build dry run is not a Wasm benchmark.

Every scene contains exactly 10,000 drawable leaves: 5000 shapes, 2500 24-point freehand/highlighter strokes, 2000 text/sticky elements, 400 arrows and 100 image references. Seed `0x5eed`. Original sparse (100,000×100,000), dense/image-heavy (1600×900) and 64-group hierarchy distributions are unchanged. A new normal fixture spreads the same mix over **8000×4500** world units; the fixed 1× panning viewport sees about 200 leaves in Chrome, without reducing document size. Four controlled originals are **1024×1024** normally or **2048×2048** for image-heavy (16 / 64 MiB logical source RGBA), reused by 100 references. Image import/codecs and 100 unique originals remain untested.

The suite has 11 short workloads and one 180-second continuous-navigation/update stress workload. Camera windows are 10 seconds and movement is 5 seconds, each with one-second warmup and one-second timing drain. Directional zoom covers approximately 0.223–4.482×. Oscillation is 1×±2%, approximately 12 cycles per configured sweep. Normal editing holds 1× and pans ±100/50 world units. Static redraw deliberately invalidates the painter every tick; it is not idle.

**Engine timings:** `stage=max(build,raster)` per `FrameTiming`; build, raster and total span remain distinct. Vsync timestamp differences measure cadence of delivered engine frames, not physical presentation. Browser cadence near 16.7 ms has scheduling jitter; 50–300 ms intervals expose multi-frame stalls. Counts are delivered timing records, not a verified presented-FPS measurement. All retained samples means all received callbacks in the selected window, not independently verified presentation completeness. The one-second timing drain may miss exceptionally late callbacks, especially with multi-second native cache jobs; drain completeness needs further audit.

**Custom timings:** query and paint recording are CPU stopwatches. Tile `recordCpu` measures recording; `imageAwaitWall` includes asynchronous engine work/queue waiting, not isolated GPU execution. Build wall includes both. Synthetic controller/pointer-to-next-paint timing excludes hardware, pre-Flutter dispatch, raster, presentation and scanout.

Percentiles use nearest rank. The reference stress delivered only 2288 frames, all retained by the original 2400-sample buffer. Final Phase 0.2 capture uses a bounded **12,000** samples, enough for this 180-second/60 Hz run; validation asserts observed==retained. The excluded first tile prototype retained only its final 2400/5980 stress frames. Its truncated stress percentiles are not used in the final comparison. Added sampler regression verifies early slow frames survive a long fast tail.

Each stress variant uses the same elapsed-time camera function and 250 ms commit timer policy, but slow rendering coalesces timer callbacks; actual commit/frame counts differ and are reported. The separate 256-commit microbenchmark has identical fixed operation counts. Runs are sequential, one final primary suite per variant, not statistically repeated thermal-controlled trials or approved release-device measurements.

## 5. Measured Chrome before/after

All times ms. Triples are **P50 / P95 / P99** of the actual slower engine stage. N is before→after delivered sample count. Full distributions are in [summary.json](../benchmark_results/phase02/summary.json) and raw aggregates.

| Workload | N | Reference | Tile candidate | Vsync interval P95 before→after |
| --- | --- | --- | --- | --- |
| sparse / camera | 599→593 | 2.199 / 3.099 / 3.600 | 2.200 / 3.500 / 14.300 | 17.400→17.401 |
| normal / normalEditing | 599→597 | 2.800 / 3.300 / 3.601 | 2.700 / 3.301 / 3.601 | 17.199→17.500 |
| dense / camera | 420→369 | 3.700 / 46.400 / 55.000 | 2.800 / 5.300 / 283.500 | 50.599→17.601 |
| dense / zoomIn | 376→520 | 3.800 / 44.701 / 99.500 | 3.400 / 4.400 / 5.301 | 60.000→17.500 |
| dense / zoomOut | 409→481 | 3.800 / 44.600 / 76.500 | 3.200 / 4.500 / 145.000 | 60.601→17.300 |
| dense / overview | 600→591 | 3.799 / 4.801 / 6.200 | 3.799 / 4.800 / 6.000 | 17.200→17.599 |
| dense / oscillation | 296→600 | 2.500 / 134.500 / 160.500 | 3.100 / 4.899 / 5.300 | 165.801→17.301 |
| dense / staticRedraw | 597→601 | 3.099 / 4.601 / 5.401 | 3.200 / 4.200 / 4.899 | 17.300→17.700 |
| dense / movement | 195→193 | 14.399 / 15.601 / 16.600 | 14.700 / 15.700 / 16.000 | 27.200→27.301 |
| imageHeavy / camera | 350→379 | 4.000 / 48.400 / 147.600 | 3.200 / 4.500 / 282.901 | 52.900→17.599 |
| deepHierarchy / camera | 410→372 | 3.899 / 54.700 / 62.701 | 2.901 / 4.601 / 314.401 | 60.900→16.901 |
| dense / stress | 2288→5984 | 45.500 / 144.200 / 161.000 | 3.200 / 131.500 / 161.299 | 197.300→221.900 |

### Dense timing decomposition

P95 ms. None of these columns is physical input-to-photon latency.

| Workload/variant | Build | Raster | Total span | Query CPU | Paint-record CPU | Synthetic update→paint |
| --- | --- | --- | --- | --- | --- | --- |
| camera/reference | 8.500 | 46.400 | 50.400 | 3.200 | 6.401 | 7.000 |
| camera/candidate | 5.300 | 2.400 | 6.101 | 3.100 | 0.401 | 3.899 |
| oscillation/reference | 31.301 | 134.500 | 165.500 | 3.000 | 25.901 | 27.300 |
| oscillation/candidate | 4.899 | 1.299 | 5.200 | 3.401 | 0.300 | 4.100 |
| stress/reference | 55.700 | 144.200 | 196.801 | 1.600 | 46.801 | 48.600 |
| stress/candidate | 74.801 | 122.300 | 221.600 | 2.101 | 38.500 | 40.100 |

Candidate cold dense navigation P99 is **283.500 ms**, with cadence P99 **317.599 ms**. Lower P95 does not erase those stalls. During oscillation→static redraw, cumulative raster builds are **225→225**, showing reuse without rebuilding unchanged content. Text layout count stays 2000; no zoom-triggered layout path was introduced.

Dense camera tile-build wall P50/P95/P99: **22.000 / 142.000 / 174.701 ms**, max **181.101 ms**. Recording P95 **11.101 ms**, image-await wall P95 **132.900 ms**. These directly expose asynchronous cache cost that warm foreground paint timing can hide.

Dense hit-testing after remediation: P95 **0.200 ms**, 256 queries after 32 warmups, candidate P95 91. No adversarial all-overlapping-hit guarantee is inferred.

### Commit and regeneration cost

Fixed 256 timed single-leaf moves after 16 warmups; total includes scene update, renderer/index synchronization and cache invalidation, but not later raster work:

| Strategy | Reference P50/P95/P99 | Candidate P50/P95/P99 |
| --- | --- | --- |
| fullReconstructionReference | 11.300 / 13.100 / 22.500 | 11.599 / 12.701 / 23.300 |
| incrementalTotal | 0.000 / 0.100 / 0.101 | 0.000 / 0.101 / 0.101 |
| incrementalGeometry | 0.000 / 0.100 / 0.101 | 0.000 / 0.100 / 0.101 |
| incrementalSynchronization | 0.000 / 0.000 / 0.100 | 0.000 / 0.000 / 0.101 |
| incrementalIndex | 0.000 / 0.000 / 0.100 | 0.000 / 0.000 / 0.100 |

One visible-element commit invalidated **1** tile(s) and built **1**. Synchronous CPU was **0.000 ms**, while commit→needed-raster-ready wall time was **19.900 ms**. The reference whole overview rebuild was **135.900 ms**. These are one-observation diagnostics with different global/local work scopes, not a rebuild P95 or a proof every move meets 16.7 ms. Timer-quantized zero CPU values mean below browser timer resolution. Last resolved/synchronized counts are 1/1.

Reference full reconstruction uses the current constructor/full synchronization, runs first, and is not an exact historical resolver replay. The original incremental scene contract is preserved.

## 6. Memory, cache churn and lifecycle

Each final web suite completed 16 dense/image-heavy renderer creation→paint→mutation→cache regeneration→disposal cycles. Owned image/paragraph counts and tile bytes are zero after disposal. These are logical handle checks, not proof of driver memory return. They do not substitute for a longer full editor-widget lifecycle/asset-import pressure test.

Stress runs:

- reference: 182.071 seconds including warmup/drain, 589 committed updates. Approximate JS heap during checkpoints: initial 243.6, peak 349.8, final 97.7 MiB. Final forced-GC V8 used heap 44.4 MiB (before GC 51.2 MiB).
- candidate: 182.029 seconds including warmup/drain, 702 committed updates. Approximate JS heap during checkpoints: initial 170.7, peak 244.5, final 111.4 MiB. Final forced-GC V8 used heap 48.7 MiB (before GC 120.4 MiB).

Candidate stress cache: peak **63.49 MiB**, final **60.47 MiB**; 561 builds, 69 evictions, 432 invalidations, 0 discarded results, 0 errors. Cumulative tile-build wall time **34849.884 ms** includes overlapping application/GPU waiting and is not total extra CPU or frame time. Published-byte bounds held throughout reported checkpoints and final validation.

Settled two-second candidate idle check: **0 canvas paint callbacks**. This does not mean zero compositor work or power use. JS heap/forced GC excludes full CanvasKit/native/GPU allocation and cannot establish device memory safety. Logical bounded caching and post-GC reduction are encouraging; three minutes is not a long-term leak/pressure qualification. Native full-soak memory is unavailable in this pass.

## 7. Input scheduling

- before: 120 software drag steps plus 24 wheel events; pan/zoom canvas checks changed (True/True). Pointer receipt→next paint-record completion P50/P95/P99 **29.600 / 32.301 / 45.100 ms**, N=143; timestamp-order regressions 0.
- after: 120 software drag steps plus 24 wheel events; pan/zoom canvas checks changed (True/True). Pointer receipt→next paint-record completion P50/P95/P99 **1.800 / 3.601 / 28.300 ms**, N=143; timestamp-order regressions 0.

One local monotonic Stopwatch is used; browser/native timestamp epochs are never subtracted. Events can coalesce, and a subsequent cache repaint can satisfy the proxy; this is not per-event presentation validation. Hardware, dispatch before Flutter receipt, raster, presentation and scanout are excluded. **Physical ≤33 ms input-to-photon remains untested, not an observed failure.** Real trackpad, touch/stylus and high-speed capture remain manual/device work.

## 8. macOS versus Chrome and profiling limits

Both final native profile builds compile with the installed SDK. The native reference delivered ten short workloads, then stopped delivering frames after hierarchy readiness. Process CPU was observed at 0%; desktop window inspection/activation failed twice with a service error, and a fresh inspection after reset timed out. Foreground/occlusion status could not be verified. The exact cause of stopped delivery is unconfirmed; it must not be classified as a measured renderer failure or a network failure.

The earlier native reference also received an intrusive process sample and was explicitly excluded. The surviving partial reference is `macos-incomplete-visibility.json`, `complete:false`. Native numbers vary substantially from historical Phase 0.1 and are not used to claim a platform speedup or a completed acceptance gate.

The final native candidate attempt records 10 workloads; complete=False, diagnosticComplete=True. These are bounded/uncontrolled diagnostic observations, not a full native qualification:

| Scene/workload | N reference→candidate | Partial reference P95 | Candidate diagnostic P95 |
| --- | --- | --- | --- |
| sparse/camera | 599→597 | 3.086 | 4.859 |
| normal/normalEditing | 600→600 | 10.246 | 2.170 |
| dense/camera | 334→29 | 117.278 | 1105.856 |
| dense/zoomIn | 305→111 | 131.585 | 161.819 |
| dense/zoomOut | 325→315 | 129.586 | 10.039 |
| dense/overview | 600→357 | 14.619 | 14.881 |
| dense/oscillation | 63→600 | 469.558 | 8.194 |
| dense/staticRedraw | 595→600 | 6.113 | 5.565 |
| dense/movement | 115→102 | 60.896 | 55.449 |
| imageHeavy/camera | 299→21 | 128.092 | 1158.005 |

The native candidate shows a substantial cold-path regression in this diagnostic: dense raster P95 **1105.856 ms** (29 frames), with per-tile image-await P95 **1115.386 ms** versus tile-record CPU P95 **13.644 ms**. Dense camera records **zero full-viewport tile hits** while images are still being prepared. Warm oscillation later records 600 frames at P95 **8.194 ms**. This is evidence of a costly cache-generation/fallback path; foreground uncertainty and one run prevent a clean platform ranking or a robust native tail guarantee. Native image-heavy camera has only 21 delivered timings. Diagnostic own-process RSS, sampled at 1 Hz and excluding full driver/other-process accounting, peaked at **776.5 MiB**; no three-minute native heap/pressure qualification was completed.

Chrome primary comparison is controlled for browser/backend/viewport and completed independently; native/window conditions differ, so it is not evidence Chrome is intrinsically slower. Native uses Skia/Metal (established in Phase 0.1 traces), web CanvasKit/ANGLE Metal. Web main-thread recording and engine/raster work differ; new CPU/await/frame metrics are reported separately rather than equating the implementations.

A separate initial reference trace attempt timed out before producing trace artifacts. It is excluded and does not invalidate the completed reference primary suite. Successful matched follow-up windows are saved as `web-reference-zoom-trace.*` and `web-candidate-zoom-trace.*`: 1 ms CPU sampling, 7–10 seconds after the normal-editing result during the first dense camera sweep. The reference has 2955 CPU samples, mostly idle/program/sorting; the candidate has 2900, additionally including CanvasKit Wasm and 44 `readPixels` self samples. This is consistent with extra image-generation/readback work, not proof of an isolated GPU bottleneck. Both contain compositor/GPU command-buffer events; custom Phase 0.2 markers are absent in these CDP captures. See `profiling-summary.json` for counts and limitations. These diagnostic runs stop after three workloads and correctly have `complete:false`, `diagnosticComplete:true`. CPU/compositor traces are diagnostic windows, not hardware GPU timers. No Windows/Android/iOS/Safari/Edge runtime claim is made. Android devices were unavailable; iOS simulator discovery previously stalled; Windows needs another host.

## 9. Tests and checks actually executed

- `flutter analyze --no-pub`: no issues after final implementation.
- `flutter test --no-pub`: **46 passed**; `flutter test --no-pub --platform chrome`: **46 passed**.
- After strengthening the long-soak percentile assertion, `test/benchmark_scene_test.dart`: **12 passed native and 12 Chrome**.
- New cache regressions: uniform translucent highlighter across a tile seam; preserved RTL ink across seams at origin/1e9; 100 zoom oscillations without extra builds; bounded LRU/oversized-view fallback; precise invalidation; actual in-flight revision/disposal races; unrelated mutation retention; completed off-view image reuse; controlled raster failure without endless retries.
- Existing affine/hierarchy/camera/culling/hit-testing/highlighter/image and incremental update regressions remain green. No debug test timing is used as production performance evidence.
- Profile web reference/final candidate suites completed all 12 workloads plus diagnostics and software input. Summary validates matching environment/viewport, complete frame retention, cache byte limits, zero reported cache/application errors and 32 disposal cycles.
- Native profile builds succeeded; runtime completion limits are explicit above. A bounded diagnostic is not marked complete.
- Formatting, script syntax and artifact/hash checks are recorded in `benchmark_results/phase02/validation.json` after execution. Reproduction is in README.

No dependency download/upgrade was required. The initial new test syntax and lint issues were corrected before final builds. Browser diagnostic timeouts and native service failures are collection/runtime availability issues with unconfirmed underlying causes, not proven application compilation failures.

## 10. Files changed in Phase 0.2

| File | Change |
| --- | --- |
| `lib/src/benchmarks/scene_tile_cache.dart` (new) | Bounded scale-keyed raster cache, precise pending/resident invalidation, LRU, build timings and disposal. |
| `lib/src/benchmarks/scene_renderer.dart` | Optional tile owner/recording, transform-region invalidation, cache repaint notifier and preparation accessors. |
| `lib/src/benchmarks/benchmark_canvas.dart` | Cache repaint listening, viewport/DPR forwarding; existing world geometry and selection retained. |
| `lib/src/benchmarks/benchmark_page.dart` | Opt-in candidate, new workloads/soak, frame cadence and partial regeneration diagnostics. |
| `lib/src/benchmarks/benchmark_fixtures.dart` | Moderate-visibility normal fixture with unchanged 10K category mix. |
| `lib/src/benchmarks/frame_samples.dart` | Configurable bounded sample count; old 2400 default retained. |
| `lib/src/benchmarks/benchmark_telemetry.dart` | Same bounded capacity option for full-soak CPU/visibility metrics. |
| `test/tile_cache_test.dart` (new) | Nine cache correctness/resource/zoom regressions. |
| `test/benchmark_scene_test.dart` | Verify longer capture retains early slow frames. |
| `tool/run_native_benchmark.py` | Independent memory collection, visible readiness, honest bounded-stop status. |
| `tool/run_web_benchmark.mjs` | Configurable timeout/trace trigger, final V8 GC, progress and bounded failure snapshots. |
| `tool/summarize_phase02.py` (new) | Validate matched primary targets and complete distributions. |
| `benchmark_results/phase02/` (new) | Primary, prototype/excluded, partial native, diagnostics, configuration, summary and validation evidence. |
| `README.md` | Reproduction and cache/measurement limits. |
| `docs/phase-0.1-report.md` | Link to this follow-up; preserve historical data. |
| `docs/phase-0.2-report.md` (new) | This report. |

`main.dart`, the pure Dart document/geometry/camera contracts, spatial grid, dependencies, SDK versions and platform runners/configuration are unchanged. No migration or configuration step is required for the existing app. Synthetic cache pixels are generated at runtime; no production assets were added.

## 11. Unresolved items classified

| Item | Classification | Evidence/meaning |
| --- | --- | --- |
| Cold raster creation stalls / missing responsive cache-job budget | Confirmed performance bottleneck | Large P99/cadence intervals and tile-image await wall time; warm P95 alone masks it. |
| Sustained dense update/navigation above 16.7 ms P95 | Failed measured acceptance criterion | Final full-distribution stress row; do not substitute warm/static results. |
| Full native completion / controlled visibility | Untested requirement | Incomplete/bounded collection; not a proven rendering failure. |
| Physical input and presented-frame latency | Untested requirement | Software next-paint proxy only; absence is not an observed latency failure. |
| Long-running heap/GPU pressure, real imported assets and mobile budgets | Untested requirement | Three-minute JS/logical-cache evidence is limited, not proof of leak freedom or safe total memory. |
| Context-loss/non-resolving image-job recovery and broad fractional/DPR fidelity | Untested requirement | Covered race/error regressions do not exhaust those conditions. |
| Final release baseline devices and any differentiated stress budget/LOD policy | Provisional target requiring product approval | The existing 16.7 ms target remains in force. No replacement budget or fidelity degradation is adopted. |

## 12. Recommendation and exact next work

Retain the pure Dart geometry, scene deltas and resource ownership. Keep this cache opt-in until cold build and repeated invalidation behavior are bounded. Do not finalize one global overview or unrestricted asynchronous tile generation as the production policy.

The smallest remaining rendering work is to test composition of ready tiles with live drawing only in missing regions, preserving paint order, instead of waiting for the entire viewport before any tile reuse. Establish a measured per-job raster budget (evaluate smaller dirty regions/tiles or staged preparation), prevent live rendering plus cache generation from creating long stalls, and repeat full-distribution cold/update tests. Sparse/cheap views should be evaluated for bypassing raster allocation rather than filling the cache with mostly empty tiles. Active-move static/dynamic reuse still needs an ordered representation preserving z-order.

Keep **16.7 ms** for the normal viewport and the currently required dense/overview acceptance gate. If a differentiated product policy is desired, review normal editing, warm overview, cold transitions and pathological overlap as separate categories, with explicit tail/input/memory limits and visual examples. A higher stress budget or temporary coarser rendering requires approval; neither is implemented or presumed accepted here.

Complete controlled native qualification, broader target-device runs, real input capture, longer memory/pressure tests and missing fidelity/failure cases before advancing. These missing measurements are separate from the observed stress failure. No further speculative cache rounds or Phase 1 work are started by this report.
