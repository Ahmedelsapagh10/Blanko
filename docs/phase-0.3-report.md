# Phase 0.3 — Sustained updates, cold caches and architecture gate

Date: 17 October 2026; collection spans 16–17 October. Scope: rendering foundation remediation only. Phase 1 remains blocked pending the decision below. Historical [Phase 0.2 evidence](phase-0.2-report.md) is preserved.

**Decision: NO-GO for Phase 1.** The corrected candidate repairs Chrome historical stress P95 (133.2→5.9 ms) and retains warm navigation, but Chrome dense interactive edits and native sustained updates still fail 16.7 ms. Two native windows are control-contaminated and explicitly excluded. Tile caching stays disabled by default. No next phase is started.

## Benchmark audit

1. The historical stress workload changes **one leaf**, `element-0`, each 250 ms timer callback, alternating world X translation by ±0.25. Timer callbacks can coalesce under load; it is not an identical fixed-count replay.
2. Only its transform/geometry changes. Camera pan/zoom runs independently on every animation tick; text, style, paths, content and structure remain unchanged.
3. Each camera tick schedules rendering. The Phase 0.2 cache returns false when any requested tile is missing, causing full visible vector/paragraph recording while tile generation also runs. A commit invalidates intersecting resident tiles and affected pending work. It does not reconstruct the resolved scene.
4. The scene is **not static between commits**: the camera continuously varies approximately 0.223–4.482×. Cache scale transitions and edits are combined intentionally in this extreme workload.
5. `stage=max(build,raster)` uses Flutter `FrameTiming`. Query/paint recording, mutation, index updates and invalidation use CPU stopwatches. Tile image-await wall time includes engine queueing/raster work. No isolated GPU execution timer, physical input-to-photon or actual presentation timestamp is available. Vsync timestamp differences describe delivered engine-frame cadence.
6. Constructor-reference microbenchmarks, initial preparation and 16 renderer disposal cycles precede stress and are outside its measurement window. One-second warmup/drain still run its mutation timer. Cold zoom-bucket generation and invalidation are intentional measured work. Renderer preparation is reported separately, including images, entry types and spatial-index construction.
7. This is extreme repeated committed transforms plus continuous navigation, not an ordinary drag preview followed by one command. The intended future command layer should commit an immutable delta and keep transient previews separate; no command/history system was added. New fixed-camera normal/dense single-element, 16-element and offscreen cases complement this test.
8. Historical P50 3.2/P95 131.5 ms and 432 invalidations show intermittent expensive work, but aggregates cannot attribute individual stalls. The new capture retains timestamped frame/commit series. A fixed-camera comparison isolates update-triggered work from zoom transitions. Proximity to a scheduler timestamp is association, not proof of GPU causality.

## Implemented experiment and ownership

The new candidate is explicitly opt-in: both `PHASE02_TILES=true` and `PHASE03_RECOVERY=true` are needed. Tile caching remains disabled by default. The default overview path is retained.

The final cache composes ready raster regions with full-detail live drawing clipped to the union of missing regions. It merges affected indices before drawing so an element crossing several missing tiles is recorded only once, preserving source paint order. If every tile is missing, it uses the original single direct draw. Hard region clips prevent a translucent seam from being blended twice. Original geometry and text remain authoritative.

The initial 256-pixel experiment with 16 ms job pacing and per-region live draws is rejected. It reduced stress P95 to 39.1 ms but regressed dense navigation to 198.401 ms versus the matched reference's 3.4 ms. Neighboring missing regions repeated entries spanning their boundaries; finer tiling and paced population also increased time to cache readiness. These changes were bundled, so the measurements do not isolate each contribution. Its complete data remains under `web-small-tile-prototype*`, excluded from final paired results.

The final candidate restores 512-pixel interiors, 514×514 images (**1,056,784 logical RGBA bytes** each), the original one-in-flight-job scheduling, and the same 64 MiB published cap (63 images). One in-flight image, pictures, uploads and engine resources are additional. Budgeted preparation was evaluated and rejected in this form; no hard raster-job duration guarantee is claimed. No lower-resolution placeholder or content omission was introduced.

`SceneRenderer` remains the owner of text/path entries, synthetic originals, spatial index and optional cache. The cache owns images and its repaint notifier; the page owns session replacement, camera and telemetry. Scene deltas and the index remain authoritative. Late affected jobs are discarded, unrelated tiles survive, and disposal releases owned handles. Active movement still uses direct drawing to preserve source order. No new engine, dependency, state-management framework or platform policy was adopted.

The update audit found no full-scene resolution on matching leaf deltas. Validation/synchronization visits changed indices; the index updates only changed entries. Chunk directories are shallow-copied (scaling with scene chunks), not 10,000 newly resolved nodes. Nonmatching base tokens intentionally use full synchronization. Tile invalidation scans a bounded resident cache; viewport queries still allocate candidate sets/lists and sort visible indices. Text layout and paths remain prepared once per renderer; current count telemetry alone does not prove cumulative allocation freedom.

## Method, environment and limits

Apple M4 / 10 logical CPUs / 16 GiB, macOS 26.5.1, Flutter 3.41.9 stable, Dart 3.11.5; no upgrades or package adoption. Chrome 155.0.8059.82 uses hardware ANGLE Metal / Apple M4, CanvasKit JavaScript profile builds, fresh headless processes, 1200×796 at DPR 1. Native builds are profile, with CPU sampling and forced GC disabled for primary collection. RSS sampling is independent of Dart heap or GPU accounting. Exact configuration, hashes, raw aggregates and test logs are in `benchmark_results/phase03/`. Hashes describe the final working tree; intermediate source snapshots and the primary web binary were not archived. This is a configuration-reproducible experiment, not a bit-for-bit archive of every build.

All fixtures retain 10,000 leaves: 5,000 shapes, 2,500 24-point strokes, 2,000 text/sticky elements, 400 arrows, 100 references to four controlled originals. Originals are 1024×1024 normally and 2048×2048 for image-heavy scenes; logical source RGBA is 16/64 MiB. Seed remains `0x5eed`. Normal distribution is 8000×4500, dense is 1600×900, sparse is 100000×100000; hierarchy and image-heavy fixtures are unchanged. No imported/unique image population, production editor or text mutation is simulated. First sparse-scene Dart-entry→framework-ready proxies are Chrome 423.899→360.500 ms and macOS 245.561→174.497 ms. Navigation/launch→ready is 1204.600→1102.900 ms and 1369.889→1158.442 ms respectively. These are startup observations, not verified physical first interaction.

Each paired suite has 20 results: four fixed-camera editing cases (6 seconds, nominal 10 Hz, one callback maximum per animation tick), four cold/reload windows (3 seconds, no warmup), eleven original short workloads, and the historical 180-second stress policy. Sixteen renderer create/prepare/mutate/dispose cycles remain separate diagnostics. The new cases precede the historical subset, so GPU/font warming order differs from Phase 0.2; new matched before/after results, rather than cross-phase small timing differences, assess regression. Each variant is one primary run, not repeated thermal-controlled release qualification.

Editing uses the first visible leaf or first 16 visible leaves in paint order. Offscreen testing first relocates the last leaf to (20000,20000), then mutates it at the same cadence; repaint requests are deliberately forced to assess cache reuse/culling, not to claim a real editor must repaint offscreen changes. These setups and immutable geometry are identical between variants. They are benchmark actions, not a production multi-selection or command feature.

Both frame and commit series retain up to 12,000 records. Frame series include every received timing in the selected frame window. Commit CPU series include warmup/drain activity; stress-end counts additionally include all timer callbacks. Operation counts differ when rendering coalesces callbacks and are reported. CPU timers are quantized in Chrome; zero does not mean zero cost. Synchronization includes index/invalidation/validation costs, so stage columns must not be added as independent work.

Cold-load frame samples cover scene preparation through framework readiness, and later cold windows cover cache population without discarding initial delivered samples. Framework readiness is a post-frame callback proxy, not verified physical interaction/presentation. With only a few cold-load timing records, P95/P99 may both equal the maximum; they are observations, not a stable tail estimate. Text-area testing centers the first text element in the normal mixed scene; dense loads additionally exercise many visible paragraphs. A dedicated all-text adversarial population remains untested.

Primary timings have no CPU tracing; this agent runs no builds, correctness tests or second benchmark renderer during measurement. Ambient user/system activity and thermal state are not isolated. One-second timing drains and engine callback completeness remain limitations, especially for multi-second native work. Browser vsync intervals can expose missed scheduling opportunities but are not measured screen refresh or input-to-photon. The timestamp association uses the scheduler's last frame timestamp at commit and a 100 ms window; it is not exact per-job GPU attribution. Tile recording and image-await counters are cumulative per renderer. Raster allocation, queue waits, driver uploads and isolated GPU execution cannot be separated by these stopwatches.

Early browser compilation failed when disk space was exhausted. Only regenerable project caches were removed; the user then freed space. Both full correctness suites and final profile builds ran successfully afterward. An interrupted local-server session was restarted before final collection. These collection/setup failures are not renderer performance results.

## Chrome profile results

All durations ms; triples are P50 / P95 / P99 of `max(build,raster)`. N is the complete delivered frame count. Each variant uses the same fixture, elapsed-time camera curve, profile mode and viewport; coalesced callbacks and frame-weighted visibility distributions differ. These are not presented-FPS measurements.

| Scene / workload | N before→after | Reference stages | Final candidate stages | Cadence P95 before→after |
| --- | --- | --- | --- | --- |
| normal / editSingle | 355→360 | 0.901 / 12.801 / 14.500 | 0.900 / 10.901 / 12.901 | 17.600→17.300 |
| dense / editSingle | 147→300 | 3.399 / 59.000 / 64.200 | 0.401 / 42.200 / 43.799 | 87.100→47.200 |
| dense / editMulti | 27→29 | 163.400 / 168.600 / 168.800 | 155.601 / 159.500 / 162.500 | 223.300→209.200 |
| dense / editOffscreen | 350→324 | 0.901 / 5.300 / 7.100 | 0.800 / 4.201 / 5.800 | 17.200→17.399 |
| dense / reopen | 178→178 | 0.500 / 1.300 / 1.401 | 0.700 / 1.800 / 2.099 | 17.401→17.500 |
| dense / coldZoom | 133→138 | 0.599 / 1.100 / 1.599 | 0.700 / 1.800 / 2.101 | 17.399→17.400 |
| normal / coldTextArea | 174→176 | 0.500 / 1.199 / 1.400 | 0.601 / 1.701 / 1.899 | 17.300→17.500 |
| dense / reopen | 178→180 | 0.401 / 1.200 / 1.300 | 0.800 / 1.601 / 1.800 | 17.500→17.500 |
| sparse / camera | 599→591 | 1.000 / 2.699 / 11.599 | 1.400 / 3.401 / 18.201 | 17.500→17.401 |
| normal / normalEditing | 595→599 | 1.000 / 1.800 / 2.400 | 1.500 / 3.500 / 3.800 | 17.301→17.500 |
| dense / camera | 360→449 | 2.000 / 3.400 / 315.900 | 2.699 / 4.299 / 159.601 | 17.600→17.699 |
| dense / zoomIn | 520→513 | 2.000 / 2.900 / 6.000 | 3.199 / 4.200 / 4.900 | 17.500→17.500 |
| dense / zoomOut | 469→547 | 2.000 / 2.901 / 169.500 | 2.899 / 3.901 / 7.000 | 17.500→17.500 |
| dense / overview | 584→598 | 2.500 / 3.000 / 3.299 | 3.500 / 4.299 / 4.801 | 17.300→17.201 |
| dense / oscillation | 597→596 | 2.101 / 2.400 / 2.600 | 3.000 / 3.901 / 4.500 | 16.800→17.400 |
| dense / staticRedraw | 598→596 | 1.699 / 1.901 / 2.100 | 2.700 / 4.000 / 4.500 | 16.800→17.101 |
| dense / movement | 175→196 | 15.899 / 17.401 / 20.500 | 14.599 / 15.500 / 16.100 | 30.800→26.500 |
| imageHeavy / camera | 357→454 | 2.500 / 5.400 / 308.599 | 3.201 / 4.801 / 90.300 | 17.600→16.901 |
| deepHierarchy / camera | 369→436 | 2.400 / 4.801 / 327.200 | 3.201 / 4.800 / 273.300 | 17.599→17.200 |
| dense / stress | 5971→7801 | 2.400 / 133.200 / 164.300 | 2.199 / 5.901 / 140.399 | 218.801→18.800 |

The historical stress P95 now passes 16.7 ms **in this Chrome run**, with all 7,801 delivered samples retained. Its P99 remains 140.399 ms and cadence P99 221.801 ms; it is not consistently smooth or proven 60 FPS. Dense navigation 4.299 ms and oscillation 3.901 ms P95 preserve the practical Phase 0.2 warm improvements. The new normal editing case (about 199 visible leaves in the same 10K document) is within the provisional budget.

**Dense interactive editing still fails:** one visible leaf at nominal 10 Hz is 42.200 ms P95; 16 selected leaves are 159.500 ms. Both see about 5,638 leaves at fixed 1×. Actual commits are 59→58 (single), 28→30 (multi), and 59→54 (offscreen); slow work coalesces the intended rate. No uniform fixed-count end-to-end editing throughput claim is inferred.

### Pipeline evidence and confirmed cause

Matching deltas resolve/synchronize one entry for leaf updates and 16 for the multi case. Chrome stress commit CPU P95 is **0.201→0.201 ms**, versus stage P95 **133.200→5.901 ms**. Geometry, index and invalidation are separately recorded in `summary.json`; typical P95 values are 0.1–0.2 ms and include browser timer quantization. Full reconstruction remains a separately executed diagnostic, not the production update path.

In the reference, **344/364 slow stress frames** occur within 100 ms of a commit's scheduler timestamp; the remaining-frame population has stage P95 4.099 ms. Fixed-camera single editing gives 58 slow frames, all near commits, while offscreen editing has none above 16.7 ms. This supports periodic post-invalidation rendering as the dominant sustained-update cost, not continuous full-scene mutation or text-layout reconstruction.

Final single-edit paint recording P95 falls **28.300→11.901 ms**, raster P95 **27.500→4.700 ms**, but engine build P95 remains **42.200 ms**. Tile preparation plus foreground recording still exceeds the UI budget. Multi-edit raster dominates at **159.500 ms**, despite commit CPU P95 **0.301 ms**. The outer viewport query P95 is about 1–2 ms in these cases; missing-region queries are included in paint-record CPU; rewriting the document engine or index is not justified by this evidence.

Stress uses **381 mixed paints** and 497 missing regions while ready pixels survive. Whole-viewport live fallback is avoided on partial misses. Tile record CPU P95 remains **50.400→49.300 ms**; image-await wall P95 falls **179.100→71.900 ms**, and build wall P95 **183.301→89.500 ms**. Fewer full live redraws reduce foreground work and engine contention; this does not make atomic cache jobs cheap or establish isolated GPU timings.

### Cold behavior

The cold-load frame population contains three delivered records per reload in this capture. First dense reload stage P95/P99 (the observed maximum with N=3) is **252.000→239.699 ms**; text-centered normal reload **128.099→130.500 ms**; second dense reload **122.300→128.200 ms**. Framework readiness is **490.399→492.400 ms**, **221.700→247.400 ms**, and **185.000→198.699 ms** respectively. Initial process sparse readiness is separately recorded in raw `ready` data.

These preparation stalls are **not removed from the evidence** by showing the mostly cheap subsequent 3-second cold windows. The first zoom animation windows have maximum received stages only 4.899/3.600 ms, yet deliver 133/138 timing records. Cache work can execute before the first animation tick or between delivered frames, so those percentiles omit initial command delay. They are not cold-latency evidence. The supplemental wall audit starts before dispatch and waits for needed cache handles plus framework paint completion. The inherited load sample is not a new load for `coldZoom`.

The normal/dense entry preparation spends roughly 67–75 ms in 2,000 text layouts on the reference, plus synthetic image creation, paths, fixture generation and index construction. This is synchronous preparation, distinct from later cache rasterization. Cold raster work additionally includes recording, engine queue/allocation and image creation; exact font initialization versus glyph/driver cost is not isolated. Warm text/path caches are retained across zoom and localized transforms.

Eviction/reconstruction is exercised by repeated zoom buckets and the long navigation/update sweep. Stress cache eviction counts are **69→71**, builds **554→584**, invalidations **425→453**, zero cache errors/discarded results. Different actual commit/frame counts mean these totals are not per-operation speedups. The rejected fine-tile/pacing experiment demonstrates that spreading submissions alone can worsen cold responsiveness and navigation.

## Memory, lifecycle and input

Bounded Chrome stress memory uses approximate JS heap checkpoints; MiB below. The final five checkpoint mean is a short terminal-window estimate, not proof of a plateau. Renderer caches, retained result arrays and browser instrumentation all contribute.

| Variant | Initial | Peak | Last checkpoint | Last-five mean | Final forced-GC V8 used |
| --- | --- | --- | --- | --- | --- |
| before | 252.1 | 286.7 | 101.9 | 86.0 | 46.9 |
| after | 173.0 | 227.5 | 79.4 | 85.0 | 47.6 |

Each suite completes 16 dense/image-heavy renderer creation, cache preparation, mutation, regeneration and disposal cycles, plus repeated page scene/session reloads. All checked renderer-owned images, paragraphs and tile bytes are zero after disposal. Tile peak is 63.49 MiB in both primary variants; final is 60.47 MiB, 60 resident images, no cache errors. Stress duration is 182.031→182.064 seconds including warmup/drain, with 699→717 committed callbacks.

These checks bound logical cache ownership and demonstrate disposal in the tested cycles. They do not prove driver memory return, native/GPU leak freedom, long-term pressure tolerance, full widget/process editor recreation or mobile safety. JS/V8 heap omits CanvasKit/native/GPU resources; process RSS also has shared/native allocations. No retained scene-history chain was introduced. In-flight engine image work cannot be cancelled; affected late results are discarded and disposed.

The software probe sends 120 drag steps and 24 wheel events after timing collection. Both variants change the sampled canvas after pan and zoom, with 143 coalesced pointer-receipt→paint samples. P50/P95/P99 are **1.500/3.000/16.401 ms** before and **1.900/2.900/29.400 ms** after. This proxy ends at paint recording; it excludes hardware, OS dispatch before Flutter, raster, GPU/presentation and scanout. It does not demonstrate that a particular event was presented or that physical input meets 33 ms. Real mouse/trackpad, touch/stylus and high-speed capture remain unvalidated requirements, not observed latency failures.

## macOS profile results and cache safety

Both native suites execute all 20 workloads and 16 renderer disposal cycles. The 800×600 DPR 1 client window is raised and visually checked during each 45-second startup delay. The reference records no viewport/lifecycle changes. The candidate records **two lifecycle changes in dense camera and two in static redraw**. Those two candidate rows (†) are uncontrolled diagnostics and excluded from clean comparison/acceptance claims. Other rows record zero changes, but continuous foreground/occlusion is not independently monitored. Native canvas is 800×346 (movement 800×326), smaller than Chrome; platform numbers are not a direct ranking.

| Scene / workload | N before→after | Reference P50 / P95 / P99 | Candidate P50 / P95 / P99 |
| --- | --- | --- | --- |
| normal / editSingle | 360→359 | 1.169 / 6.286 / 7.133 | 1.193 / 5.869 / 6.554 |
| dense / editSingle | 321→322 | 14.224 / 15.867 / 16.856 | 1.652 / 9.646 / 16.486 |
| dense / editMulti | 192→182 | 15.610 / 16.715 / 17.454 | 15.385 / 31.353 / 33.255 |
| dense / editOffscreen | 353→350 | 1.093 / 3.478 / 16.062 | 0.995 / 3.138 / 13.650 |
| dense / reopen | 170→166 | 0.907 / 1.604 / 15.464 | 0.505 / 1.422 / 29.235 |
| dense / coldZoom | 160→156 | 1.069 / 2.259 / 15.457 | 0.974 / 8.763 / 31.106 |
| normal / coldTextArea | 180→179 | 1.101 / 1.402 / 1.520 | 0.902 / 1.145 / 1.398 |
| dense / reopen | 165→161 | 1.093 / 1.638 / 14.217 | 0.915 / 1.238 / 27.346 |
| sparse / camera | 600→598 | 2.050 / 4.536 / 5.183 | 1.831 / 4.758 / 5.609 |
| normal / normalEditing | 600→600 | 1.257 / 2.360 / 2.621 | 1.668 / 2.208 / 2.432 |
| dense / camera † | 250→298 | 3.039 / 182.390 / 216.947 | 3.050 / 122.513 / 258.546 |
| dense / zoomIn | 520→596 | 2.878 / 4.877 / 34.719 | 2.750 / 4.086 / 6.266 |
| dense / zoomOut | 578→600 | 2.468 / 4.211 / 5.495 | 2.264 / 3.872 / 4.570 |
| dense / overview | 600→600 | 3.061 / 3.458 / 4.165 | 3.038 / 3.477 / 3.742 |
| dense / oscillation | 600→600 | 3.144 / 4.158 / 4.529 | 2.615 / 3.881 / 4.199 |
| dense / staticRedraw † | 600→599 | 2.754 / 3.524 / 3.922 | 2.578 / 3.151 / 3.612 |
| dense / movement | 300→300 | 9.380 / 10.032 / 10.337 | 9.880 / 10.784 / 11.145 |
| imageHeavy / camera | 230→262 | 2.457 / 185.956 / 202.367 | 2.567 / 147.046 / 267.461 |
| deepHierarchy / camera | 248→303 | 2.590 / 190.760 / 210.701 | 2.235 / 76.814 / 275.530 |
| dense / stress | 5786→6775 | 2.784 / 141.415 / 213.048 | 2.568 / 89.102 / 187.212 |

Clean native stress remains a measured failure: **141.415→89.102 ms P95**. Fixed-camera single editing improves **15.867→9.646 ms P95**. The clean reference cold dense navigation is **182.390 ms P95**; candidate camera **122.513 ms P95** is lifecycle-contaminated and cannot establish its improvement or qualification. Its diagnostic P99 is 258.546 ms. The old Phase 0.2 incomplete native diagnostic is not a matched baseline. The native regression is not demonstrated resolved: keep tile caching disabled by default and adopt no platform-specific policy.

Native stress recording P95 is **8.817→9.015 ms**, but image-await wall P95 is **381.083→355.103 ms**, longer than the 250 ms mutation period. **264→162 stale jobs are discarded**, versus zero in Chrome. Published cache peak remains below capacity, so these stress discards are not capacity-driven off-view discards: affected in-flight revisions repeatedly become stale before publication. Mutation CPU is small; asynchronous raster/queue work dominates. Exact driver/backend/upload causality is not isolated. This measured cost difference does not justify two independent rendering engines.

The native callback drain is one second while some cache jobs exceed three seconds. All *received* samples are retained, but delivery completeness/presentation are not independently proven. Full control-flow completion is not release qualification or proof every late raster callback was attributed to the preceding window. The supplemental wall audit addresses initial cold delay without claiming physical presentation.

Native RSS is sampled at 1 Hz, in MiB below. It is process memory, not isolated Dart heap/GPU memory. The terminal mean uses the final 30 seconds of stress; after-cycle values use the nearest RSS sample. No forced GC or CPU profiling runs during these primary suites.

| Variant | First process sample | Peak across suite | After 16 cycles | Stress initial | Stress last-30s mean | Last sample |
| --- | --- | --- | --- | --- | --- | --- |
| before | 0.0 | 724.2 | 724.2 | 545.3 | 405.1 | 384.8 |
| after | 0.0 | 863.7 | 781.8 | 752.6 | 694.2 | 646.9 |

## Explicit cold wall-time audit

The supplemental profile audit fixes two measurement problems without changing the historical workload: it starts a Stopwatch before the command, and normalizes zoom before reloading so initialization cannot prewarm the next scale bucket. Validation requires new builds at every first zoom and actual evictions. The earlier loader-reuse audit is retained and excluded from the final pair. Historical scene loading can still prepare a prior camera region before its post-frame reset; the opening clock includes that work. Global font/driver initialization is not isolated by recreating a renderer.

The figures below are **single observations per case, milliseconds**, not percentile estimates. Each pair is reference→candidate. They end when required image handles are prepared and a framework frame has completed. Live vector content may be drawn earlier: **cache readiness is not first visible interaction, input-to-photon, or proof the UI froze for the entire interval**. Raw engine frame records are retained alongside these wall metrics. The raw `ready` entries additionally retain first-process framework readiness; neither proxy proves physical presentation.

| Target / scene / session | Open→cache + framework paint | New zoom bucket | Visible commit→cache | Return after eviction |
| --- | --- | --- | --- | --- |
| web / normal / 0 | 240.200→241.399 | 103.200→87.500 | 14.800→14.301 | 47.300→45.600 |
| web / normal / 1 | 221.500→215.100 | 94.500→90.601 | 13.500→13.600 | 45.400→46.800 |
| web / dense / 0 | 580.300→580.500 | 546.600→550.200 | 26.100→37.801 | 450.900→464.301 |
| web / dense / 1 | 514.500→535.500 | 478.100→507.100 | 48.300→45.300 | 438.300→461.500 |
| macos / normal / 0 | 214.290→198.106 | 63.973→80.306 | 14.410→14.510 | 17.569→30.218 |
| macos / normal / 1 | 163.611→163.687 | 31.448→82.600 | 14.488→14.219 | 17.346→21.479 |
| macos / dense / 0 | 580.710→581.431 | 481.183→514.242 | 46.546→45.369 | 447.256→451.870 |
| macos / dense / 1 | 595.502→613.378 | 464.535→481.209 | 45.177→29.393 | 433.718→452.483 |

All sixteen cases have zero recorded lifecycle/viewport changes, actual cold zoom builds and forced eviction. Four controlled originals stay 1024×1024 in these normal/dense cases. Empty views deliberately occupy slots to force eviction, followed by a return to the edited source view. Cache limits hold and old renderer images/paragraphs are zero after each reload. These bounded cycles do not establish long-term GPU/process memory safety. Cold preparation remains expensive; the mixed strategy does not substantially solve initial zoom or reconstruction wall cost.

## Files, packages and verification

Phase 0.3 changes are limited to:

| File | Change |
| --- | --- |
| `lib/src/benchmarks/scene_tile_cache.dart` | Opt-in mixed composition, one union clip for missing regions, original tile footprint, cache counters; original reference/default policy retained. |
| `lib/src/benchmarks/scene_renderer.dart` | Deduplicate affected indices in source order; expose index preparation and synchronization/validation/invalidation CPU timings; pass optional recovery policy. |
| `lib/src/benchmarks/benchmark_page.dart` | Fixed-camera editing, cold/session cases, bounded frame/commit series, explicit cold wall audit and unchanged historical stress actions. |
| `test/recovery_cache_test.dart` (new) | Seven opt-in/default, batching, localized update/index/order, alpha, fractional RTL/large-world, disposal and zoom reconstruction regressions. |
| `tool/run_native_benchmark.py` | Optional no-event timeout; preserves honest incomplete status and terminates only its own app. |
| `tool/summarize_phase03.py` (new) | Validate equivalent full profile configurations, all 20 rows, untruncated series, cache limits/errors and disposal; summarize CPU stages and commit proximity. |
| `benchmark_results/phase03/` (new) | Raw paired results, rejected prototype, environment, audit, logs, summaries and validation evidence. |
| `README.md` | Reproduction and measurement limits. |
| `docs/phase-0.2-report.md` | Follow-up link only; historical findings unchanged. |
| `docs/phase-0.3-report.md` (new) | Engineering findings and decision options. |

No new package, SDK upgrade, state-management/DI pattern, schema, command/history engine, production drawing tool or storage feature was introduced. Pure Dart scene/geometry/camera, spatial-grid source, fixtures, `main.dart`, dependency files and platform runners/configuration are unchanged. No migration or Android/iOS configuration action is required.

Executed correctness checks: `flutter analyze`; `flutter test --no-pub` (**53 passed**); `flutter test --no-pub --platform chrome` with the installed Chrome (**53 passed**). Debug test timing fixtures are excluded from performance evidence. The fractional text test compares additional mixed-composition error against the same warm resampling baseline, then checks seam opacity and retained ink; it does not require inherently different vector and resampled glyph antialiasing to be bit-identical. Existing geometry/transform, incremental hierarchy, culling/hit, cache race/error and renderer tests are preserved.

Strict paired validation checks profile mode, matching scene/workload/viewport, correct opt-in flags, every received frame retained, unchanged viewport/lifecycle, bounded cache bytes, zero cache errors and 16 zero-owned-resource disposal cycles. The explicit `--allow-native-lifecycle-diagnostics` mode retains two flagged native windows as diagnostics, marks that pair as control-unclean, and cannot certify it as a clean acceptance comparison. Completion is required; the old incomplete native captures are not substituted. Script syntax, formatting and final artifact/hash checks are recorded separately in `validation.json`.

## Remaining issues and architecture risk

| Issue | Classification | Consequence |
| --- | --- | --- |
| Chrome dense fixed-camera single/multi edits exceed 16.7 ms P95 | Measured performance failure | A passing historical stress P95 does not qualify dense interactive editing. |
| Native sustained updates remain at 89.102 ms P95 | Measured performance failure | Opt-in tile strategy is not globally promotable. |
| Native camera/static candidate control contamination | Unvalidated clean comparison | Two lifecycle-affected windows cannot certify native cold-navigation recovery. |
| Long cold jobs and large cadence/P99 gaps | Measured bottleneck; final cold-tail acceptance criterion requires product approval | Keep reporting complete distributions and explicit wall latency; do not silently exclude initial work or invent a larger accepted budget. |
| Initial cold animation-window timing omitted pre-first-tick work | Verified instrumentation defect in that metric | Explicit cold command-to-cache-ready audit supplements it; short cold-window percentiles are not used as cold responsiveness proof. |
| Physical input, GPU execution/presentation attribution | Unvalidated requirement | Software paint proxy and engine timestamps cannot establish these outcomes. |
| Long-term native/browser/GPU memory pressure and full editor lifecycle | Unvalidated requirement | Bounded renderer/session reload evidence is insufficient for a production safety claim. |
| Imported unique assets, broader fractional/DPR/font fidelity, driver/context loss | Unvalidated requirement | Controlled originals and sampled seam/race tests do not exhaust them. |
| Final baseline devices, differentiated extreme/cold/fidelity contract | Acceptance criterion requiring product-level approval | Existing 16.7 ms remains unchanged; no new contract was adopted. |

No unresolved document/geometry correctness defect was established in tested coverage. The rejected per-region duplicate drawing was corrected before final collection. Remaining gaps are not asserted as bugs without evidence.

The current cache invalidates whole spatial tiles for transforms. At low scale one tile can contain much of the 10K scene, and several selected elements can invalidate most required pixels. Immutable incremental geometry alone cannot bound that raster work. Text/style/content changes still require explicit renderer replacement in this transform-only spike; a future document engine must not interpret that as a production keystroke policy. Stable z-order, conservative paint bounds, transparency and resource lifetime must constrain any finer invalidation or dynamic-layer design.

## Decision and approval options

**NO-GO for Phase 1.** Historical Chrome sustained-update P95 is repaired in this run, and normal editing/warm navigation are encouraging. Chrome dense interactive editing and the clean native sustained-update window remain measured failures; native cold camera recovery is not cleanly qualified. Missing physical-input and long-term memory validation are additional gaps, not the reason for declaring an observed timing failure. Keep both tile caching and recovery disabled by default. No platform-specific cache policy or second rendering engine is adopted.

The next action is review of this Phase 0.3 evidence and selection of an explicitly approved path. Costs below are **engineering estimates**, not measured delivery times or promised performance gains:

| Option | Work and estimated cost | Expected benefit | Risks and stopping rule |
| --- | --- | --- | --- |
| A. One targeted optimization | Dirty-subrectangle reuse/repair inside existing tiles, conservative old/new paint bounds, and a cheap/empty-region policy. About 3–5 engineering days for a bounded prototype, plus device qualification. | Avoid rebuilding a tile's thousands of unchanged elements for a small edit; likely addresses remaining localized-update work. Magnitude is unmeasured; first cold population may remain expensive. | Stale pixels, alpha/gutter/ordering errors, unsafe font/arrow bounds. Approve one time-boxed experiment, preserve normal/navigation gates and report cold tails; stop if it fails rather than iterating automatically. |
| B. Limited rendering architecture change | Prototype ordered retained static ranges with an explicit transient/edit representation, keeping the existing scene/index and bounded resources. About 5–10 engineering days for feasibility, then cross-platform qualification. | Reduce repeated static recording/raster work during interaction and give preparation scheduling a clearer boundary. No performance guarantee is inferred from the current spike. | Layer/z-order complexity, overdraw, memory pressure and platform behavior; avoid a wholesale document or engine rewrite. Require an architecture review and equivalent benchmarks before adoption. |
| C. Revised performance contract | About 1–2 engineering days of product/engineering review to define supported visible density, cold-state behavior, P95/P99/cadence/input/memory limits and any approved visual trade-off, followed by validation. | Makes an intentionally narrower supported interaction envelope testable, if the product accepts it. | Product compromise; cannot retroactively call current failures passes, omit cold work, lower fidelity or relax 16.7 ms without approval. The current implementation still needs evidence against the new contract. |

Recommendation: **A, as one bounded experiment**, if the full 10K dense interaction contract remains required; choose B only if its expected complexity is justified after review, or C if product requirements genuinely change. None is started. No Phase 0.4, Phase 1, storage, advanced tools or export work begins without explicit approval.

Manual/device validation still needed: keep the native viewport visible during reproduction; inspect pan/zoom, RTL text and translucent strokes across fractional zoom and DPR changes; test real mouse/trackpad and touch/stylus latency with presentation capture; run longer heap/GPU pressure and full editor recreation tests on approved Windows/macOS/Web/Android/iOS baselines. Other platform runtime performance, full context-loss recovery and hard-cold font/driver initialization are not qualified here. No additional commands are needed to apply the code; reproduction commands are in README.
