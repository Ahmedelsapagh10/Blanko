# Performance governance and evidence

Current execution override2026-10-19: speculative caching, dense/font experiments and repeated benchmark investigation are paused. MVP-01 direct editor is functional; Debug launch/widget results are not production performance. All unresolved10K/16.7ms, input/presentation, memory and platform obligations remain in M14 Production Hardening. Historical “next experiment” sections below are superseded scheduling, preserved evidence. No new benchmarks ran for MVP-01.

Updated 2026-10-18. Interactive target remains provisional P95 16.7 ms at 60 Hz on recorded baseline hardware. Stage=max(build,raster) is not presented FPS. Physical input P95 ≤33 ms remains unvalidated. Explicit cold command→cache-ready clocks are not first visible interaction or physical presentation. Extreme all-visible stress and realistic editing are distinct named workloads; neither silently replaces the other.

Historical evidence: [Phase 0](phase-0-report.md), [0.1](phase-0.1-report.md), [0.2](phase-0.2-report.md), [0.3](phase-0.3-report.md). Raw aggregates/environment/validation under `benchmark_results/phase03/`. Latest Apple M4/16 GiB observations: Chrome stress stage P95 133.2→5.901 ms, dense fixed-camera single 42.2 ms and multi 159.5 ms; native stress 89.102 ms. Two native windows are lifecycle-contaminated. These are recorded historical results, not reruns in this session. Gate fails; cache remains default off.

Required workload coverage: normal editing, sparse/dense navigation, extreme overview, zoom oscillation, sustained local single/multi/offscreen updates, cold open/zoom/eviction, text/images, group transforms and future export. Report P50/P95/P99, received/retained counts, cadence proxies, mutation/query/paint/raster stages, input proxy limits, preparation, memory/peak/logical resource bytes and revisions/actual commits. Future save/export latency joins the matrix when implemented.

One in-flight asynchronous raster limits concurrency, not duration. Logical 64 MiB image cap excludes originals, a pinned/in-flight image, pictures, engine/driver copies. Do not infer a memory plateau from a short terminal mean or disposal counters. Primary timing collection excludes CPU tracing/forced GC; separate diagnostics may use them and must be labeled.

Next experiment WB-0115–0117: dirty-region tile repair with identical dimensions/fixtures and opt-in flags. Measure replayed entries/dirty area/builds/discards, record CPU and image-await wall, fixed-camera dense edits and cold costs first. If correctness or focused benefit fails, reject before an expensive full sweep; if promising, run full independent Chrome/macOS navigation/stress/memory controls. New results belong in `benchmark_results/execution-01/`, never overwrite historical baselines.

## Execution 01 — measured dirty-repair diagnostic

Apple M4 / 16 GiB, macOS 26.5.1, unchanged Flutter 3.41.9/Dart 3.11.5; Chrome 155.0.8059.82 with hardware ANGLE Metal/CanvasKit. Same final source hashes, separate profile binaries/flags: `benchmark_results/execution-01/profile-manifest.json`. Both flags keep existing tile/recovery true; only `WB_DIRTY_REPAIR` differs. Dataset/category mix unchanged: 10K leaves, 100 image references to four controlled 1024×1024 originals. Browser canvas/window and native viewport differ; do not rank targets directly.

Three six-second fixed-camera editing windows per variant, nominal 10 Hz with callbacks coalescing. Actual commits differ and are retained. Engine stage P95 milliseconds, reference→repair:

- Chrome normal single: **14.901→7.399**, samples 360→349, commits 59→58.
- Chrome dense single: **40.599→22.099**, samples 299→357, commits 59→58.
- Chrome dense multi: **163.099→159.699**, samples 28→32, commits 29→33.
- macOS normal single: **5.124→1.262**, samples 359→338, commits 60→58.
- macOS dense single: **9.765→6.832**, samples 334→336, commits 59→59.
- macOS dense multi: **30.532→37.603**, samples 185→146, commits 55→52.

All received frame series retained; zero recorded lifecycle/viewport changes and cache errors. Native 800×632 overall window raised and visually checked before runs; focus telemetry unavailable and continuous occlusion not monitored. Native process RSS sampled at 1 Hz across this short diagnostic peaked 340.2→338.7 MiB; not a memory plateau/leak test or total GPU allocation. Tile peaks 12.09 MiB Chrome / 8.06 MiB native, both below 64 MiB. No forced GC/CPU tracing during collection.

Normal local replay drops to ~9–11 entries per repaired tile. Dense single replays hundreds of overlaps; multi covers much of the populated area. Native dense-single record CPU P95 4.762→2.720 ms, image-await 63.206→63.134 ms; multi await 56.199→69.052 ms and record 3.180→3.436 ms. Native stale results 55→52 in multi accompany 55→52 actual commits, not a demonstrated per-operation reduction. Chrome dense-multi await 38.899→70.599 ms. Exact GPU/driver/queue attribution is not isolated. `repairPixels` counts declared damage only; each output remains full 514×514, so it is not actual raster allocation/work.

This is **not full-suite qualification**. Warmup/scene preparation can precede short windows, the one-second callback drain does not independently prove every late produced frame was delivered, and first cold cache-ready wall clocks were not recollected. Historical Phase 0.3 cold/navigation/stress remain preserved; no improved cold or physical presentation claim is made. No long-duration memory or real device qualification is inferred.

Decision: useful local benefit, insufficient gate result and native multi regression. Keep default-off. Per ADR-005, stop before an expensive full sweep of this already failing candidate and continue WB-0119 ordered retention feasibility. Cold/full navigation/stress/memory/input validation remains mandatory for an accepted strategy. Strict reproduction: `python3 tool/summarize_dirty_repair.py --target web` / `--target macos`; summaries always mark `renderingGateQualified=false`.

## Execution 02 — bounded vector-range diagnostic

Same M4/16 GiB, Flutter/Dart and 1024×1024 synthetic originals. `WB_RETAINED_EXPERIMENT=true` disables tile/overview preparation in **both** arms; vary only `WB_RETAINED_RANGES=false/true`. Reference is direct rendering, so these numbers cannot be compared causally with Execution 01's tile reference. Rendering source hashes and profile artifacts: `benchmark_results/execution-02/profile-manifest.json`. New pure document files are unimported by the benchmark and excluded from that compilation.

Chrome hardware ANGLE Metal/CanvasKit, three six-second windows per arm, zero warmup, all received distributions retained. Normal viewport had 199 visible leaves; dense fixed-camera viewport had **5,638**, from a 10,000-leaf document. This is not the all-10K-visible navigation stress case. Stage P50/P95/P99 ms, direct → vector:

- Normal single: 1.6/3.5/4.7 → 2.899/3.601/4.3; samples 360→358, commits 58→59.
- Dense single: 28.5/36.3/39.5 → 27.5/34.6/38.801; samples 146→202, commits 53→54.
- Dense multi (16 active): 28/35.9/38.2 → 28.2/32.3/39.1; samples 150→197, commits 55→53.

Dense paint-record CPU P95 drops 31.3→0.4 ms single and 31.2→0.8 ms multi. Candidate raster P95 remains 34.6/32.3 ms and dominates its engine stage. This supports a remaining raster/replay bottleneck; it does not isolate GPU driver/queue execution. Cache estimates peak at 2,287,640 bytes (2.18 MiB) / 40 resident pictures for dense, below 16 MiB/128 handles; borrowed images/paragraphs, in-construction candidates and engine/driver memory are excluded. Lifetime builds include initial scene painting before the explicit reset; the first measured paint rebuild is not hidden.

Command→first-paint-record wall ms: normal 43.6→34.101, dense single 151.4→155.1, multi 61.5→72.399. Candidate first retained CPU record is 2.201/36.899/33.8 ms. These are first-use **CPU recording** clocks after resetting pictures in an already-loaded scene, excluding raster completion/presentation and cold app loading. They do not establish interactive cold readiness. No physical pointer events are generated by these edit workloads.

Zero recorded viewport/lifecycle/focus changes on Chrome, focused=true, no collector/cache errors, IDs/actual 1-or-16 resolved/synchronized changes verified. Strict reproduction: `python3 tool/summarize_retained_ranges.py --target web`. Bounded output always marks gate=false. Browser JS heap snapshots are not total CanvasKit/GPU memory or a leak test. No forced GC/CPU tracing during primary collection.

System disk/VM pressure was material during builds and Chrome collection: free space briefly ~117 MiB, swap allocated 6 GiB, compressed physical pages ~6.36 GiB. Free space recovered without deletion; exact disk-delta attribution is unknown without a pre-build VM baseline. See `environment-pressure.json`. These runs are diagnostic under that limitation, not clean release qualification. A first macOS capture used the wrong delay define and is explicitly excluded (`macos-direct-excluded-startup.json`); corrected paired collection is tracked separately.

Vector retention fails the unchanged dense 16.7 ms target on Chrome. Per ADR-006, reject production promotion and defer a full cold/navigation/soak sweep of this insufficient vector-only candidate. WB-0119 remains unchecked for actual bounded on-screen layer reuse feasibility; full rendering/input/memory gate remains mandatory and unresolved.

Corrected macOS pair: same startup delay (`PHASE01_AUTORUN_DELAY_MS=20000`), 800×600 logical content / 800×632 window; AX Raise and sparse pre-suite screenshot verified during delay for both arms. Normal visible leaves 89, dense 2,764. Stage P50/P95/P99 ms:

- Normal single: 1.725/5.05/5.624 → 3.527/6.136/6.722; samples 359→359.
- Dense single: 14.425/15.946/16.817 → 13.828/15.263/15.831; samples 356→355.
- Dense multi: 14.261/15.765/16.239 → 13.978/15.254/16.127; samples 359→358.

All native windows executed 60 actual commits per arm. Dense paint CPU P95 2.883→1.207 / 2.872→1.215 ms; candidate raster P95 15.263/15.254 ms. Normal stage regresses despite recording reuse. First-use wall ms normal 17.589→16.884, dense single 15.536→15.978, multi 20.992→24.675; candidate first record CPU 0.195/5.294/6.413 ms. Cache peak 491,104 approximate bytes / 40 pictures; sampled process RSS peak 264.2→278.25 MiB across short runs, not proof of leak or plateau. Final focus is unavailable (`null`); zero recorded transitions and pre-run screenshots do not prove continuous visibility. No full stress/navigation/cold/physical/soak claim. Strict macOS summary accepts only the corrected capture. These narrower native viewport results do not qualify all-visible stress or compensate for Chrome's failure.

Build failures retained: corrected native attempt hit ENOSPC; one retry failed with an interrupted-current-directory error during a tool/runtime interruption. Only two identified ignored October17 compiler hashes (~194 MiB) removed. A later retry completed after external free space recovered to ~8 GiB. Exact cause of that recovery is not established. No user apps/system data were deleted or killed. Both final source pairs are unchanged at their recorded hashes; source and artifact ownership are separate from subsequent pure-Dart document additions.

## Execution03 — actual on-screen layers, bounded profile diagnostics

2026-10-18, Apple M4/16GiB/macOS26.5.1, Flutter3.41.9/Dart3.11.5, Chrome155.0.8059.82 hardware ANGLE Metal. No upgrades/packages. Same final-source hashes in `execution-03/profile-manifest.json`; direct/vector/layers vary only experiment defines. All optimized, tiles/overview off, no warmup, four6-second edit windows per arm; synthetic100ms committed-edit cadence.100 image references reuse four1024×1024 RGBA synthetic originals (16MiB decoded pixels). Full received stage/build/raster/P50/P95/P99/series, commit widths, CPU and first-use clocks retained in raw JSON and strict summaries. Stage=max(build,raster), not presentation/FPS/input-to-photon.

Chrome controlled four-row stage P95 ms, direct → vector → layers:
- Normal single:4.699 →3.5 →3.4.
- Dense single:32.5 →25.699 →25.6.
- Dense16-element prefix:32.5 →25.899 →25.2.
- Dense16-element interleaved:33 →25.301 →33.7 (layers fully fall back).

Chrome canvas1200×542,window1200×796,DPR1; visible normal199/dense5,638 from10,000-element documents. Exact IDs/paint indices/viewport/images match arms. Each dense layer prefix keeps one static subtree, lifetime builds/submissions2,reuses55/56 and zero fallback; no repeated engine submission of that unchanged subtree. Dense paint CPU P95 becomes1/1.299ms versus27.6/27.5ms direct, yet raster P95 remains25.6/25.2ms. Vector recording alone already0.3/0.4ms. Thus actual layer retention does not establish the Chrome16.7ms gate. First command→paint-record wall ms direct/vector/layers: normal32/29.201/32.401,dense single135.8/140.301/144.3,prefix58.199/60.699/62.3,interleaved58.7/61.399/61.2. Layer first record CPU dense32.701/30.5ms, not hidden by warmup. These are not complete cold readiness or interaction clocks.

macOS comparison is **dense-only, partial**. First direct capture had two lifecycle-contaminated rows; retained as `macos-direct-lifecycle-excluded.json`. Direct repeat has one lifecycle change in normal/editSingle. Full four-row validator correctly rejects both baselines. Explicit `--dense-only` retains all three clean dense rows from the repeat and excludes normal from every arm; no matched native normal claim. Vector/layers rows record zero lifecycle changes. Pre-run CUA AX Raise/sparse screenshot before20-second autorun delay on all arms; native focus unavailable and continuous occlusion unmonitored. See native-visibility/exclusion JSON.

Clean native dense stage P95 ms, direct → vector → layers:
- Single:15.172 →14.87 →3.965.
-16-element prefix:15.16 →15.046 →5.057.
-16-element interleaved:14.725 →14.836 →14.903 (layers fully fall back).

Native canvas800×346,window800×600,DPR1; visible dense2,764. These are not cross-target rankings or10,000-visible stress results. Layer dense raster P95 is1.28/1.709ms; paint CPU1.498/1.584ms. One static subtree, builds/submissions2,reuses58 each; actual dense commits direct59/59/60,vector60/60/60,layers59/59/59. First-use wall dense single13.94/15.507/14.07ms,prefix20.802/22.419/20.83ms. Native benefit is promising for this fixed-camera prefix workload, not navigation/zoom/full rendering qualification. Reported engine layer-cache peak bytes are0 in these captures: stable subtree submissions/reuse do not prove automatic GPU raster caching.

Interleaved row selects16 entries spread through visible source order. Unchanged64MiB raster-exposure cap causes complete direct fallback on both targets: no published layers/picture bytes/exposure/reuses remain;55 Chrome/59 native fallbacks. Lifetime one pre-run build/submission is legitimate and separate from the reset first-use probe. Peak published exposure10,663,720B Chrome /6,025,888B native and approximate pictures2,249,588B/472,608B; these exclude driver/engine duplication, borrowed resources and temporary preparation. No total-GPU-memory guarantee.

Native48 RSS samples per arm over~49.8s: peaks direct303,424KiB,vector292,080KiB,layers281,184KiB; endings280,512/267,504/258,560KiB. These include startup/scene replacement and differing lifecycle controls; no leak/stability or causal memory-reduction conclusion. Browser evidence includes logical owned-resource estimates, not full process/GPU memory. Long soak still pending.

Validation: `python3 tool/summarize_layers.py --target web --interleaved` and native with `--target macos --interleaved --dense-only`. Eight invalid fixture checks rejected, including dense lifecycle and visible-density mismatches. `renderingGateQualified=false`; defaults stay off. No full cold/navigation/all-visible/image-heavy/soak/physical-input/device qualification from these diagnostic runs. Reassess per ADR-011 before further tuning: investigate installed web backend choice with observable backend/isolation controls, preserve CanvasKit/Safari fallback and budget. Native layer path remains an experiment. No benchmark passed the full acceptance gate.

## Execution04 — observed web engine/compiler/thread configurations

2026-10-18, unchanged Flutter3.41.9/Dart3.11.5, Apple M4/16GiB/macOS26.5.1 and Chrome155.0.8059.82 hardware ANGLE Metal. Three serial fresh-browser Profile arms from matching sources, same vector-retained path (layers/tiles/overview off), four6-second rows, zero warmup, same canvas1200×542/DPR1 and active IDs/indices/visible counts. Actual dense visible5,638, normal199 from10K documents.100 image references/four1024×1024 originals/16MiB logical decoded pixels. Stage=max(build,raster), not presentation/FPS. All12 frame+commit series and distributions retained in execution-04/web-backends-summary.json and raw reports.

Stage P95 ms, CanvasKit → skwasm single-thread → skwasm multi-thread:
- Normal single:3.5 →4.8 →5.92.
- Dense single:25.009 →29.3 →38.275.
- Dense prefix16:24.785 →29.2 →33.155.
- Dense interleaved16:24.995 →31.201 →32.335.

Compiler flags alone were not accepted as backend proof: report dart2js/dart2wasm, installed loader globals and actual `_skwasm_isMultiThreaded()` export agree with successful app/engine resource responses. CanvasKit and multi had local COOPsame-origin/COEPrequire-corp; single had absent headers/isolation/SAB. Multi additionally observed an actual worker blob URL and SAB/isolation=true. All selected rows have zero recorded viewport/lifecycle/focus changes. No engine/runtime error or resource-probe overflow.12 deliberately corrupted fixtures rejected, including false thread/backend/compiler/resource/isolation evidence, missing frames/commits, altered quantile/density/control and over-budget cache. Independent audit confirmed results and one provenance gap, recorded below.

No backend qualifies16.7ms or improves the measured dense workload sufficiently. Reject backend promotion/SDK upgrade as remediation. This compares observed configurations; it does not isolate compiler-only, isolation-only or thread-only causation, establish repeatability, or validate other browsers. Same skwasm main JS/wasm/mjs and engine bytes matched single/multi; generated bootstrap hashes differ. CanvasKit actually selected `canvaskit/chromium/…`; initial manifest hashed the generic engine path. Correct chromium JS/wasm hashes were recorded **post-capture**, matching unchanged installed SDK and current build copies. Do not describe those engine bytes as independently hashed at capture. Source hashes and main app binary hashes were captured normally.

First sparse navigation→framework READY ms: CanvasKit6,737.725; skwasm single63,377.1; multi8,349.97. Their own fixture/load-to-interactive clocks321.495/242.6/200.221ms exclude most startup. Separate fresh single-thread startup diagnostic reached READY in1,022.381ms and did not reproduce63s. It observed external Roboto WOFF2 fetch~688.5ms and a pending NotoSansArabic request at first READY. Requests aborted when the diagnostic closed are not classified as startup failures. The prior outlier's cause remains unknown; no cold-start distribution/readiness/fallback-font completeness guarantee. Benchmark text depends on external font fallback; pin licensed controlled font assets and explicit readiness before another rendering experiment. Existing profile font availability was not recorded, so no full text-fidelity qualification or sole-cause attribution.

New verification:3 host page cases,3 Chrome page cases, clean analysis. Attempted Wasm graphics3 suites failed during loading with0 test cases; a pure geometry Wasm diagnostic also executed0, remained at suite loading and was interrupted after~608s using exact owned-command/stdout verification. Flutter returned0 after interruption but printed 'No tests ran'; explicitly not a pass. No SDK changes/upgrade/workaround or production Wasm adoption. Earlier109 host/109 Chrome suite remains historical execution03 evidence, not rerun here. Short JS-heap samples exclude Wasm/GPU/process memory and cannot establish stability. Physical input, full all-visible/navigation/cold/image-heavy/soak and required platform coverage remain pending. Overall gate NO-GO.

## Execution05 — Fixed local font baseline (2026-10-19)

Controlled font readiness recovered; rendering recommendation **NO-GO** remains. New same-source CanvasKit/dart2js Chrome155.0.8059.82 Profile arms, AppleM4/16GiB/macOS26.5.1, hardware ANGLE Metal enabled. Fixed Roboto3.015 and NotoSansArabic2.012 bytes/weights/OFL audited; four font transfers completed before first READY in every arm, zero outside-origin font requests. Local COOPsame-origin/COEPrequire-corp consistent across arms; no production header recommendation. Sources/assets/FontManifest/app/all possible local engine routes hashed before capture, including observed chromium CanvasKit route. Full source hashes stable. New metrics are their own baseline; historical text/fallback/Ahem conditions differ, no font-only causal claim.

Four6s rows per fresh arm, no row warmup, canvas1200×542/DPR1. Normal199/dense5,638 visible of10,000 mixed elements, four1024² originals/100 references/16MiB decoded. IDs/paint indices/visibility/image controls match; zero viewport/lifecycle/focus changes. Every received frame and commit retained in raw reports. P50/P95/P99 engine stage milliseconds, normal single / dense single / dense prefix16 / dense interleaved16:

- Direct:2.570/4.545/5.494;25.584/33.221/34.070;25.790/33.935/35.000;25.090/33.335/36.400.
- Retained vectors:2.680/3.330/3.640;24.960/27.485/28.595;24.561/26.850/27.445;24.455/25.230/25.640.
- On-screen layers:2.685/3.305/3.505;24.570/25.675/26.495;24.380/26.495/29.865;24.515/33.959/34.620.

Layer prefix rows reuse one static subtree49/51 times,2 engine submissions; interleaved row hits complete bounded direct fallback50 times with0 retained layers/reuses. No GPU raster-cache proof or total GPU cap. Existing33 subtree/16MiB approximate picture/64MiB estimated raster exposure limits preserved. Dense command-to-first-paint-record clocks include142.910ms direct single/146.460ms vector/153.905ms layers; these are synthetic first-use observations, not physical input latency. They are retained rather than removed as warmup. Sparse/normal pass the provisional stage target in these bounded rows; every dense P95 remains above16.7ms.

First navigation-to-READY520.635/533.420/563.285ms, combined runtime asset-read/registration54.245/52.725/54.720ms. Separate fresh layers startup with all external requests blocked:READY548.517ms, blocked requests[], console warnings/errors[], complete manifest readiness. Local default Roboto is also loaded by the engine before Dart; runtime aliases are an additional bounded registration set, engine-owned until shutdown. This startup audit is not a frame benchmark or proof of universal offline startup. Prior63s outlier cause remains unproven; these runs do not assign all startup improvement to fonts.

Real-font correctness additionally exposed fractional text tile resampling before edits:1.25× view uses2× raster, warm dark-pixel counts324 direct/266 cached, mean per-channel-byte error0.7133. These threshold counts are not missing-character counts. Explicit complete direct fallback now contains nonbucket text scenes, preserving source order/alpha; original pixel bounds strengthened to exact fallback equality. Tile preparation/repair lifecycle remains; fractional tests no longer claim repaired-raster fidelity. Aligned caches separately exercised, while fractional camera/widget/device phase at matching scales remains unqualified. Previous tile zoom results cannot qualify this new fallback behavior.

Actual116 host/116 Chrome regressions and clean analysis. Asset/cmap/license audit plus paragraph stability are not full Arabic shaping/IME/Unicode/device qualification. No new native Profile run or memory/input/soak/full cold/navigation/all-visible/image-heavy qualification. Historical evidence preserved; first incomplete runner suite excluded after a TIME_WAIT port-preflight error, then all three arms recaptured. Sources, raw samples, strict summaries, startup/provenance and verification/failures: `benchmark_results/execution-05/`. No candidate promotion; retain ADR-012 hypothesis only after exact pixel/device-phase and bounded first-use/resource proofs.

Independent final audit:2,911 frames/617 commits fully recomputed,64 captured source hashes stable,21 final compiled artifacts checked and19 engine/font/manifest artifacts match across arms;18 malformed evidence copies rejected. Observed chromium engine JS/Wasm routes are in each BEFORE-capture hash set. Earlier app/bootstrap binaries were overwritten by later arms and are supported by runner-recorded hashes; no independent wire-body digest was collected. Audit command currently requires retained final build/web output; source/samples/commands remain available after later builds. `font-profile-validation.json` is the durable result and includes the post-capture validator's own hash. This validation establishes evidence integrity, not a passed performance gate.

## MVP-02 functional persistence checkpoint

78 host/76 Chrome correctness tests, normal and isolated macOS Debug builds/restarts and actual Chrome page persistence checks were executed. These are not performance measurements. Snapshot encoding/write latency at10K, memory plateau/input/presentation and all device budgets remain pending in Production Hardening. No raster/font/backend benchmark loop resumed. Development capacity was managed with targeted generated native cache cleanup, preserving app data/historical evidence/dependencies/SDKs.
