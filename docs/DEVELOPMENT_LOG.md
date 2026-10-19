# Development log

## 2026-10-17 — Execution recovery

- Read new master directive; it supersedes historical phase approval stops and authorizes local remediation and bounded independent agents.
- Inspected Git, sources, tests and Phase 0–0.3 reports/evidence. Branch `master`, two commits; large user-staged foundation/results, mixed worktree changes and untracked final Phase 0.3 artifacts preserved. No Git writes.
- Independent repository/rendering agents confirmed production editor/document/commands/storage are absent; main remains starter, benchmark_main owns lab. Stale widget issue is already fixed. Geometry/index deltas are reusable and cheap; whole-tile invalidation/raster reconstruction remains dominant.
- Reconciled all 243 original backlog tasks plus three explicit remediation subtasks (246 total), permanent instructions/source directive and required management documents. Historical verification is labeled separately; no new benchmark claim.
- Existing `.gitignore` already excludes build/.dart_tool/coverage/logs. No broad generated-artifact policy changes required. Preserve small evidence and bound new raw output.
- Flutter sandbox attempted SDK stamp refresh and was denied; requested narrowly scoped execution approval without upgrades. SDK version confirmed 3.41.9 / Dart 3.11.5. Toolchain discovery and new baseline checks in progress.
- Chosen next experiment: dirty-region repair, not smaller/paced tiles or a geometry/index rewrite. No package, platform, state-management or product-scope change.

- Fresh baseline analysis clean, 53 host tests pass; current toolchain doctor confirms macOS/Chrome, Xcode 26.2, Android licenses partly unaccepted and no connected mobile device. After opt-in prototype edits, analysis and all 16 existing tile/recovery tests pass. Raw logs are ignored; compact verification JSON is retained.

- Dirty repair implemented behind `WB_DIRTY_REPAIR` plus existing cache/recovery flags. Retains clean base pixels, bounds/merges damage, replays affected entries once and pins one cloned image during async repair. Whole-image output allocation remains; no native benefit inferred.
- Independent agent added seven regression tests; root added controlled repair failure/retry coverage. Initial seven host tests passed, but Chrome found stale old pixels/double alpha in combined exclusion-path composition (59/60 pass). Warm baseline matched, proving a new repair defect. Iterative rectangular difference clips resolved it without relaxing assertions. All eight focused Chrome and full **61 host + 61 Chrome** pass; final analysis clean. Native engine defect is not inferred.
- Compiler ENOSPC interrupted two test attempts; removed only ignored project compiler/native outputs (about 1 GiB). External available capacity later recovered to 3.2 GiB, enabling all checks. Failure logs and compact results retained.
- Current same-source matched Chrome profile reference/candidate diagnostics are underway, three realistic editing workloads only; no full gate claim. User Git index hash is unchanged.

- Matched final-source profile pairs completed on Chrome and macOS: three six-second edit cases each variant, 12 windows total, all received samples retained, no reported viewport/lifecycle changes or cache errors. Summaries strictly validate equivalent configurations and actual repair use. Native window raised/visually checked before both collections; focus telemetry unavailable and continuous occlusion unverified.
- Repair improves normal/single edits but Chrome dense still fails, native multi regresses and native image-await remains costly. Rejected promotion/full qualification sweep, preserved failed gates and selected WB-0119 ordered retained-content/transient feasibility (ADR-005). This experimental stopping-rule update does not weaken the product gate. No new cold/navigation/long-soak claims.
- Independent plan audit verified all original IDs and no cycles; fixed gate prerequisites, renderer integration dependency and independent design/font/storage research readiness. Current 22/249 verified (8.84%); production milestones remain unchecked. Disk again ~240 MiB after collection, limiting further compiler work despite project-only cleanup.

Files changed in this session:

- `AGENTS.md`: concise project/resume/quality/delegation/authorization instructions.
- `docs/EXECUTION_DIRECTIVE.md`: verbatim durable source directive.
- `docs/MASTER_PLAN.md`: original 243 tasks plus six evidence-driven remediation tasks; dependencies, acceptance, tests/status/evidence.
- `docs/PROJECT_STATUS.md`: current checked-task progress, failures, coverage and next work.
- `docs/ARCHITECTURE.md`: actual lab ownership/boundaries and limited next experiment.
- `docs/DECISIONS.md`: autonomous execution, dirty repair, Chrome fix and measured stopping/retention alternatives.
- `docs/RISKS.md`: measured failures, resource/platform/storage and staged-work risks.
- `docs/TEST_MATRIX.md`: actual 61/61 coverage, commands and pending platform/input/reliability gates.
- `docs/PERFORMANCE.md`: historical links, unchanged budgets and executed per-target diagnostic results/limits.
- `docs/DEVELOPMENT_LOG.md`: concise audit/failure/fix/verification/file record.
- `docs/HANDOFF.md`: immediate safe resume and exact next actions.
- `docs/RELEASE_CHECKLIST.md`: mandatory unchecked V1 release gates.
- `README.md`: management links and reproducible opt-in profile diagnostics; historical sections preserved.
- `lib/src/benchmarks/scene_tile_cache.dart`: conservative bounded damage, clean-image reuse, clipped live regions, stale-safe pinned async repair, resource/error telemetry.
- `lib/src/benchmarks/scene_renderer.dart`: source-order dirty replay and retained base reconstruction, optional repair flag and replay counters.
- `lib/src/benchmarks/benchmark_page.dart`: opt-in flag propagated to sessions/disposal diagnostics and reports.
- `test/dirty_tile_repair_test.dart`: eight pixel/order/RTL/large-world/replay/race/budget/disposal/failure/fallback regressions.
- `tool/summarize_dirty_repair.py`: reuse existing summarizer with strict bounded matched-profile validation and explicit no-qualification output.
- `benchmark_results/execution-01/`: small raw paired captures, summaries, provenance/verification/recovery evidence; ignored raw text logs retained locally. Previous staged/working files left as found.

No SDK/package upgrades, Android/iOS/platform configuration, migrations, staging/commits or public release actions. Manual future checks: actual input/presentation, broader DPR/asset/device coverage, long-memory pressure and lifecycle; none counted as performed.

## 2026-10-18 — Retained-range experiment resumed

- Recovered safely after an intentional interruption. No profile collector/server was started before interruption. Analysis and 13 affected existing host regressions had passed; the agent-produced nine-test file was complete but unexecuted. User index checkpoint preserved in execution-02.
- Implemented default-off vector range retention, exact visible membership checks, explicit active elements in source order, bounded picture estimates/LRU, conservative invalidation and local origins. No new dependency, architecture adoption or platform/SDK changes.
- Nine focused host tests and then all 70 host/70 Chrome tests passed. Independent read-only review found an unused overview raster in later diagnostics; guarded diagnostic/manual preparation and added retained-disposal telemetry. Full regressions rerunning after those guards.
- Added strict direct/retained bounded validator reusing existing summary logic and wrote ADR-006 before profiling. No performance claim yet. Free disk recovered to about 3.4 GiB at resume; continue sequential builds.


### Execution 02 completion checkpoint

- Final vector correctness: nine retained graphics cases, all 70 host/70 Chrome before independent document additions; unused overview preparation guarded in diagnostics/manual move. Record clocks include first cache rebuild, but stop at CPU paint completion rather than physical readiness. Final benchmark source hashes match both per-target profile pairs.
- Profile direct/vector pairs collected serially on Chrome and macOS, three six-second rows per arm. Chrome dense recording P95 31.3→0.4 / 31.2→0.8 ms while stage stays34.6/32.3 ms. Native dense stage15.263/15.254 ms at narrower density, normal regresses6.136 ms. All received samples/commits/control fields preserved. Per-target summaries and PERFORMANCE contain P50/P95/P99, first-use clocks, visible counts, estimated picture bytes and short native RSS. No gate/physical/full-suite/long-memory claim.
- First native capture used the incorrect delay flag and was excluded. Correct pair used PHASE01_AUTORUN_DELAY_MS=20000, with AX Raise/sparse screenshots before suite. Corrected build initially hit ENOSPC, retry interrupted, later completed. Never substituted the uncontrolled capture as baseline.
- Read-only audit: swap allocated6GiB, compressor physical~6.36GiB, no snapshots; project growth cannot explain capacity swings. Only ignored old compiler hashes (~194MiB) removed after build ENOSPC. After disk reached zero during handoff, removed ignored test cache plus superseded incorrect-delay native compiler cache (~202MiB). Source, profile artifacts/evidence and index retained; no user apps/data/system VM changed. External recovery to8GiB not attributed; ~348MiB after cleanup, then~118MiB at final validation.
- Independent pure-Dart document models added, reviewed and corrected for missing per-element revision/opacity plus safe integer revision range. Models contain all13 logical variants, source-relative sibling order/derived preorder, immutable snapshots and iterative ownership validation. Partial WB-0201 stays unchecked for document metadata/settings/resource manifests.
- DocumentGeometry added after profiles: one O(n) snapshot world/inverse pass, O(1) point lookups, contextual missing-ID/numeric errors. Root reviewed source/tests; no Flutter/benchmark imports or renderer integration. Nine tests include200 seeded affine routes, ±1e9 tolerance and5,000 owners.
- Final **90 host +90 Chrome tests passed**, analysis clean. Additional retained-config model/page14/14 per target, focused geometry9host; no inflated unique-case count. Six malformed collector fixtures rejected, script syntax verified. Chrome pressure observation resolved when original suite completed90 before any guarded stop matched; no test terminated/retried. Default Python external-cache write denied; redirected temporary bytecode cache successfully.
- Final index SHA matches initial execution02 checkpoint, rendering sources still match built artifacts; no staging/commits/packages/SDK/platform edits. No local server listener at cleanup; own collectors/tests finished. No background execution.
- WB-0202/0203/0204/0210 verified: **26/249=10.44%**. WB-0119 remains IN_PROGRESS for actual layer reuse; WB-0114 unresolved. ADR-007 rejects vector promotion and reassesses layer footprint/engine-memory constraints, preserving all product targets.

Files created/modified in Execution 02 (earlier Execution 01/pre-existing changes remain separate):

- `lib/src/benchmarks/scene_picture_cache.dart` (new): bounded ordered vector retention, active/live ranges, local origins, membership/delta invalidation, fallback, estimates/ownership counters.
- `lib/src/benchmarks/scene_renderer.dart`: opt-in cache owner/record/sync/paint/dispose integration; source-order direct fallback.
- `lib/src/benchmarks/benchmark_page.dart`: experimental flags, equivalent direct/reference setup, actual active IDs, first-use reset/reporting and overview/disposal guards.
- `lib/src/benchmarks/benchmark_telemetry.dart`: command-to-first-paint-record proxy with explicit reset.
- `test/retained_ranges_test.dart` (new): nine fidelity/order/camera/mutation/overflow/budget/disposal regressions.
- `tool/summarize_retained_ranges.py` (new): strict matched profile/control/actual-edit/budget validation, always unqualified output.
- `lib/src/document/element.dart` (new): opaque IDs, immutable typed content/style, explicit safe revisions and opacity.
- `lib/src/document/document.dart` (new): immutable version/revision/order snapshot, lookup/children/preorder and structural validation.
- `lib/src/document/document_geometry.dart` (new): snapshot world/inverse transform resolution and contextual mapping errors.
- `test/document_model_test.dart` (new): eleven model/invariant/boundary cases.
- `test/document_geometry_test.dart` (new): nine transform/property/numerical/deep-hierarchy cases.
- `README.md`: reproducible retained experiment flags, collectors/validators and limits.
- `docs/MASTER_PLAN.md`: evidence/status for four verified independent tasks; parent vector/layer experiment and complete document contract remain unchecked.
- `docs/ARCHITECTURE.md`: implemented model/cache/transform ownership and missing integration boundaries.
- `docs/DECISIONS.md`: ADR-006 measurement contract; ADR-007 rejection/layer reassessment; ADR-008 production contract choices.
- `docs/PROJECT_STATUS.md`:26/249 verified progress, executed90/90 checks, measured failures, coverage and environment.
- `docs/PERFORMANCE.md`: both bounded direct/vector distributions, first-use clocks, actual densities/resource estimates and limits/exclusions.
- `docs/TEST_MATRIX.md`: actual90/90 coverage, retained-config checks, malformed collector/syntax checks and pending gates.
- `docs/RISKS.md`: current raster/layer exposure, memory/disk pressure, immutable snapshot and integration/platform risks.
- `docs/HANDOFF.md`: exact safe resume actions, current evidence/capacity and unfinished work.
- `docs/DEVELOPMENT_LOG.md`: this execution/failure/fix/verification/file record.
- `benchmark_results/execution-02/` (new): paired raw reports/environment/summaries, excluded capture, source/binary/index provenance, pressure/cleanup/collector-validation/verification JSON. Raw text logs are ignored; no large traces added.

No migration, package, Android/iOS or other platform configuration changes. No user command needed to migrate. Manual qualification still required later: real mouse/trackpad/touch/IME and presentation, varied DPR/assets, device/platform/lifecycle and long-memory stress. These are not counted as performed. Next work is in HANDOFF; no phase approval required.

## 2026-10-18 — Execution03 retained layers and complete document declarations

Implemented actual framework-composited static runs around live edits, default off. Layer handles exclusively own subtrees; PictureLayer owns pictures. Preflight caps/order/fallback, exact camera/membership, camera-relative recording, active/inactive delta behavior and disposal preserve existing scene/index. Graphics suite exposed a real fractional/DPR viewport double-clip defect; fixed with inflated hard recording clip plus one exact AA outer clip without weakening assertions. Added recording-failure cleanup/retry coverage. Pure document values now include deterministic settings/title/workspace/resource/UTC metadata with explicit unresolved legacy compatibility.

Verification:109 host +109 Chrome tests/16 files per target passed in fresh sequential per-file compiler processes, source hashes unchanged. Subsequent benchmark-only interleaved/report/page lookup changes pass3 configured page cases per target. Braces-only test lint corrected; final analysis clean. Initial all-in-one/first-batch ENOSPC and initial lint failure preserved as failures. Eight malformed collector/control fixtures rejected; independent review verified source hashes, counts, metrics, caps, matching density and exclusions. WB-0201 verified;27/249=10.84%. WB-0119/0114 remain unchecked.

User explicitly authorized assistant to reclaim space. Removed ignored project compiler caches523MiB, then verified inactive Gradle8.14.3 transforms (actual free gain5.749GiB). Other work regenerated2.649GiB there; writer not identified, so did not repeatedly delete it. Removed independently verified inactive8.12/9.2.0 transforms, gain1.765GiB. Downloaded modules/SDK/current-active caches/other project outputs/user data preserved; no apps/daemons stopped. Capacity remains volatile; all tests/builds/collectors serial. No package/version/config/migration changes.

Profile from frozen same sources: Chrome four six-second direct/vector/layer rows; actual dense visible5,638. Layer stage P95 dense single/prefix25.6/25.2ms versus direct32.5/32.5, still above16.7. Native actual dense visible2,764: three validated dense-only rows, layer3.965/5.057ms versus direct15.172/15.16. Native first baseline had two lifecycle changes; repeat normal had one, so full four-row validation rejected and normal excluded from every arm. No further retry or hidden control waiver. Interleaved16 edits trigger unchanged exposure cap and full direct fallback on both targets. Lifetime subtree builds/submissions2 and reuse demonstrate retention; reported engine cache bytes0 do not prove GPU raster caching. First-use recording/RSS clocks are not cold readiness/soak/physical presentation. Full distributions and exact limitations in PERFORMANCE. Defaults remain off; no full-gate pass.

ADR-011 reassesses after insufficient Chrome vector/layer strategies. Next investigate installed WebAssembly/backend behavior with explicit runtime/isolation evidence and CanvasKit/Safari fallback; no SDK upgrade or performance assumption. Installed help confirms --wasm support, but no Wasm build/runtime test executed. Current binaries remain synthetic diagnostics.

Files created/modified in this execution (pre-existing unrelated work preserved):
- `lib/src/benchmarks/scene_layer_cache.dart` (new): bounded ordered layer ownership/retention/fallback/accounting.
- `lib/src/benchmarks/scene_renderer.dart`: layer recording/invalidation/statistics/disposal and opt-in creation.
- `lib/src/benchmarks/benchmark_canvas.dart`: composited render box; shared direct-paint/query/selection helpers and listener lifecycle.
- `lib/src/benchmarks/benchmark_page.dart`: default-off layer/interleaved flags, canvas integration and matched diagnostic metadata/active paint indices.
- `lib/src/document/document.dart`: compatible versioned settings/title/workspace/resource/metadata snapshot validation.
- `lib/src/document/document_settings.dart` (new): pure canvas/grid/asset/font/UTC metadata values and boundaries.
- `test/retained_layers_test.dart` (new):10 graphics/ownership/error tests including strict actual pixels/subtree submissions.
- `test/document_settings_test.dart` (new):9 document declaration/default/validation tests.
- `test/benchmark_page_test.dart`: existing drag/cancel/pan/zoom/disposal cases inspect either canvas widget, allowing actual layer configuration.
- `tool/run_test_batches.py` (new): fresh sequential per-file compilers, explicit success/hash manifest under capacity pressure.
- `tool/summarize_layers.py` (new): strict controlled comparisons and explicitly partial dense-only native reporting.
- `README.md`: flags, ownership limits, collectors/validators and native exclusions.
- `docs/MASTER_PLAN.md`: WB-0201 verified and WB-0119 remaining scope/evidence updated.
- `docs/ARCHITECTURE.md`: implemented layer/value boundaries and unqualified integration limits.
- `docs/DECISIONS.md`: ADR-009/010 implementation contracts and ADR-011 measured reassessment.
- `docs/PROJECT_STATUS.md`:27/249 progress, actual checks/results and remaining risks.
- `docs/PERFORMANCE.md`: profile distributions/actual densities/controls/exclusions/first-use/resource limits.
- `docs/TEST_MATRIX.md`: executed109/109, configured page coverage and batching protocol.
- `docs/RISKS.md`: current raster/fragmentation/capacity/control/platform risks.
- `docs/HANDOFF.md`: exact resume actions and checkpoint state.
- `docs/DEVELOPMENT_LOG.md`: this record.
- `benchmark_results/execution-03/` (new): raw reports, strict summaries, lifecycle exclusion, source/binary/index provenance, small source snapshot, test/control/cleanup audits and verification. No large traces. Raw text logs/builds stay ignored.

No user migration/configuration commands required. Manual qualification still pending: actual mouse/trackpad/touch/IME/input-to-photon, large/varied assets/DPR, cold/navigation/all-visible/image-heavy and long-memory/platform/device/release checks. No background work after checkpoint.

Final checkpoint:9 Dart files formatted with0 changes; Python syntax/diff check/source archive/profile source hashes/task IDs valid. Cached Git index preserved. Approximately2.34GiB free; owned collectors/server/native app absent. `execution-03/final-checkpoint.json` records exact checks.

## 2026-10-18 — Execution04 web backend observability and rejection

Implemented compiler metadata and opt-in post-timing engine/thread/resource/header/worker evidence, using inspected installed3.41.9 loader/export state. Added loopback-only optional-isolation server and strict independent3-arm validator. Kept rendering/model/cache logic, SDK/packages/platform/production web files unchanged. Three host +three Chrome page cases and analysis pass. Complete109/109 regression remains execution03 historical evidence, not rerun without a rendering change.

Actual same-source Profile vector arms, four6s rows each: CanvasKit dense single/prefix/interleaved P9525.009/24.785/24.995ms; skwasm single29.3/29.2/31.201; actual multi38.275/33.155/32.335. All12 row controls/IDs/indices/density/assets match; complete frame/commit distributions recomputed.12 malformed backend/compiler/thread/resource/header/sample/quantile/density/lifecycle/commit/budget fixtures rejected. Independent audit confirmed metrics and a provenance gap: actual CanvasKit chromium engine files were initially not hashed; correct hashes added post-capture with explicit SDK/current-copy agreement. Skwasm app/engine binaries match single/multi, generated bootstrap hashes differ. No isolated compiler/thread causal or full-gate claim. No backend promotion; budgets/defaults unchanged.

Wasm graphics3 suites fail before loading0 cases. Pure geometry diagnostic also stalls at loading, interrupted after608s using exact owned command/stdout proof; exit0+'No tests ran' is explicitly STOPPED, not PASS. No SDK workaround. A read-only CDP browser diagnostic did not return before its orchestration cell was stopped and produced no usable browser artifact; no diagnosis inferred. Preserve logs/failure and avoid more unbounded retries for a rejected backend candidate.

Navigation READY clocks6.74/63.38/8.35s include much more than app fixture/load clocks. Separate bounded fresh single-thread request diagnostic reached READY~1.02s, did not reproduce63s. It observed remote Roboto~688.5ms and pending remote NotoSansArabic at first READY; shutdown-aborted icon requests are not startup failures. Outlier cause unknown. ADR-012 selects font/version/license/readiness control recovery before further cache experiments; existing profiles cannot qualify full font readiness/fidelity. Physical input/presentation/soak/platform gate stays NO-GO;27/249 tasks checked, no inflated progress.

Files changed in this execution:
- `lib/src/benchmarks/benchmark_page.dart`: native/dart2js/dart2wasm compiler metadata only.
- `tool/run_web_benchmark.mjs`: opt-in bounded engine/resource/worker/thread/header audit, expected-backend rejection and late-error audit retention.
- `tool/serve_benchmark.py` (new): loopback build server with optional diagnostic COOP/COEP/no-store and server disposal.
- `tool/summarize_web_backends.py` (new): matched observed3-arm controls, complete distribution/commit validation and explicit nonqualification.
- `tool/inspect_web_startup.mjs` (new): bounded owned-browser request/failure/console/readiness diagnostic.
- `README.md`: commands/configuration and recorded limitations.
- `docs/MASTER_PLAN.md`: WB-0119 actual backend rejection and next controlled-font investigation, no new completion credit.
- `docs/ARCHITECTURE.md`: laboratory-only probe/server boundary and unadopted backend.
- `docs/DECISIONS.md`: execution04 protocol and ADR-012 measured reassessment.
- `docs/PERFORMANCE.md`: actual distributions/backend/thread/density/cold clocks/provenance/test failures and limits.
- `docs/TEST_MATRIX.md`: actual3+3/analysis,0 Wasm cases and strict diagnostic checks.
- `docs/PROJECT_STATUS.md`, `docs/RISKS.md`, `docs/HANDOFF.md`: current progress, failures, controlled-font priority and exact resume.
- `docs/DEVELOPMENT_LOG.md`: this record.
- `benchmark_results/execution-04/` (new): three raw reports/complete summary, source/binary/index/SDK provenance,12 negative fixtures, startup trace, test/control/stop/verification checkpoints. No large trace recordings.

No migration/config/package/Android/iOS command required. Manual platform/device/physical-input/long-memory/full-fidelity qualification remains pending. No background work after checkpoint.

Execution04 final checks: cached index and profile source hashes unchanged; source archive saved, syntax/diff/task counts valid. Managed collectors exit0 and owned server finally blocks complete; interrupted SDK harness confirms Chromium shutdown. Separate read-only CDP/final process-audit cells did not return and were terminated; residual read-only client state unconfirmed, no global process-absence claim. Final free capacity~3.27GiB. No further engineering execution after checkpoint.

## 2026-10-19 — Execution05 controlled fonts and rendering evidence

WB-0120 verified;28/250=11.20%. WB-0119 still IN_PROGRESS, WB-0114 NO-GO, WB-0715 production font policy remains unchecked. Fixed official unmodified Roboto3.015 regular/medium/bold and NotoSansArabic2.012 regular with OFL notices/source/archive/file/license hashes; no dependency/SDK/lockfile/platform upgrade. Four files1,676,168 bytes. Explicit once-per-engine lab registrations before UI/paragraphs; bounded asset waits, concurrent deduplication, retry unfinished faces, actionable failure, disposed/late gates, READY preparation metadata. Local manifest Roboto avoids engine's forced pre-Dart external default font; shared pubspec addition is explicit, production curation not assumed.

Actual root causes/fixes: first retry created error future before FutureBuilder attached; creation deferred into build. Chrome test environment ignores platform asset messages and forces Ahem, so moving load to setUpAll could not help; test-only supported asset bridge reads verified generated copies and enables actual custom fonts with downloaded fallbacks disabled. Ready-future async boundary later blocked a widget factory/error case; synchronous ready completion and skipping unnecessary renderer await preserve prior behavior. All initial failures/interrupted0/partial suites retained and excluded, never counted as a successful full run.

Genuine fonts exposed old warm raster mismatch BEFORE edits: at1.25×,2× tile resampling yields324 direct/266 cached threshold-dark pixels, mean channel-byte error0.7133; postmove322/265. These are antialias-sensitive counts, not missing-character counts. Narrow reported full ordered direct fallback for text-bearing scenes at nonbucket scale; immutable text flag once, no per-frame full-scene scan. Original bounds retained and strengthened to exact pixel/fallback proof. Aligned cache tests remain genuine cache proofs; matching-scale subpixel phase remains unqualified. Preparation/repair lifecycle retained; cache performance is not claimed for fallback. Independent read-only reviews found no blocking loader/ownership issue and endorsed this limited containment.

Executed116 host116 Chrome across17 fresh file processes per target, identical unchanged sources/assets; analysis clean, changed Dart format/diff clean. Four font assets/license/version/weight/cmap checks and four malformed cases PASS; paragraph stability does not prove shaping. Three matched CanvasKit Profile arms/12 rows: stage dense P95 direct33.221/33.935/33.335ms, vector27.485/26.850/25.230, layers25.675/26.495/33.959.5,638 dense visible of10K, canvas1200×542/DPR1. Interleaved layers fully fall back; bounds unchanged. First-use clocks kept; no warmup exclusion or candidate promotion. No new native Profile or required-device/input/soak qualification. Prior Wasm0 cases preserved, not rerun.

Font transfers all complete locally before first READY. Fresh external-blocked startup548.517ms, no external attempts/errors/warnings;52–55ms combined runtime read/registration in frame arms. Historical startup63s outlier causation unproven; new metrics not an isolated font-cause comparison. First runner suite stopped after direct arm because preflight socket lacked HTTPServer's TIME_WAIT reuse option; owned server was closed. Corrected helper, preserved incomplete suite and recaptured all arms. Independent audit fully recomputed2,911 frames/617 commits, checked64 source hashes/21 final compiled artifacts/19 stable engine/font/manifests, rejected18 malformed evidence cases. Actual chromium engine route hashed before capture; earlier app/bootstrap bytes overwritten, runner hashes retained, no wire digest claim. No heavy concurrent work during timings.

Exact files changed/created this execution (existing mixed work preserved):

- `.gitignore`: ignore only generated Chrome font fixture copies. `pubspec.yaml`: local font assets and engine-default Roboto declaration; packages/lockfile unchanged.
- `assets/benchmark_fonts/Roboto-Regular.ttf`, `Roboto-Medium.ttf`, `Roboto-Bold.ttf`, `NotoSansArabic-Regular.ttf`: unmodified fixed upstream fonts. `Roboto-OFL.txt`, `NotoSansArabic-OFL.txt`: original notices. `manifest.json`: versions/provenance/byte/archive/license digests.
- `lib/benchmark_main.dart`: awaited font gate, explicit themed aliases, failure/retry/disposal-safe builder. `lib/src/benchmarks/benchmark_fonts.dart`: engine-lifetime fixed loader/readiness/failure/timeouts/report. `benchmark_page.dart`: READY/run font report. `scene_renderer.dart`: readiness/explicit paragraph fonts, immutable text flag and reported nonbucket tile fallback.
- `test/benchmark_fonts_test.dart`:7 meaningful concurrent/failure/engine-retry/timeout/late/disposal/paragraph cases. `test/flutter_test_config.dart`, `test/support/font_assets_host.dart`, `test/support/font_assets_web.dart`: once-per-engine test preparation and conditional genuine-font browser asset bridge. `test/dirty_tile_repair_test.dart`, `test/recovery_cache_test.dart`: preserve original bounds, add exact fractional fallback pixels/counters; accurately label fallback.
- `tool/verify_benchmark_fonts.py`: stdlib integrity/OFL/SFNT/cmap audit,4 negative cases, optional hash-verified test fixture copies. `tool/run_test_batches.py`: audit/preflight and asset hashes. `tool/run_web_benchmark.mjs`: opt-in local font transfer/readiness audit and explicit font-failure rejection. `tool/start_web_benchmark.js`: retain font failures. `tool/inspect_web_startup.mjs`: optional external-blocked readiness diagnostic. `tool/run_font_profiles.py`: serial owned bounded builds/collectors/servers, pre-capture binaries/manifests/asset/source hashes and font controls. `tool/validate_font_profiles.py`: independent post-capture raw-distribution/control/manifest/provenance/negative validator.
- `README.md`, `docs/ARCHITECTURE.md`, `DECISIONS.md`, `DEVELOPMENT_LOG.md`, `HANDOFF.md`, `MASTER_PLAN.md`, `PERFORMANCE.md`, `PROJECT_STATUS.md`, `RISKS.md`, `TEST_MATRIX.md`: actual commands/ownership/ADR-013/limits/results/next actions; all historical reports/raw evidence preserved.
- `benchmark_results/execution-05/`: source/archive/provenance/raw frame+commit samples, audit/verification/summaries/startup, preserved initial failures/incomplete attempts and final checkpoint. Generated logs/builds/fixture copies stay ignored. No blanket stage/reset/commit; original index preserved.

For direct Chrome tests run `python3 tool/verify_benchmark_fonts.py --prepare-web-tests` first; batch runner does this automatically. No migration or Android/iOS/Windows configuration step. Manual/required device/Arabic shaping/IME/input/long-memory checks remain pending tasks. Next per ADR-012/013: exact device-phase pixel equivalence and bounded cold/stale/fragmentation/resource proof before selection-scoped static raster ranges; independent visual geometry contracts remain allowed. Current build/web is layers CanvasKit laboratory, not product release. No background engineering after final checkpoint.

## 2026-10-19 — MVP-01 First Usable Whiteboard

User priority supersedes the benchmark-first integration stop: usable editor now, local save/reopen next, stress hardening later with unchanged guarantees. Independent file-owned agents implemented the pure session and scene adapters; coordinator integrated UI/tests/docs and native keyboard audit. No overlap on shared contracts or Git writes.

Implemented files:

- `lib/main.dart`: replace generated counter with normal WhiteboardApp/EditorPage; keep benchmark entry separate.
- `lib/src/editor/board_session.dart`: pure-Dart production document add/world-move/subtree-delete and bounded inverse Undo/Redo; transactional validation, monotonic revisions, ID allocation, locks, source order and manifest preservation.
- `lib/src/editor/editor_scene.dart`: committed scene adapter using existing geometry/index; ordered viewport culling and precise topmost pen/shape/line hits, inherited visibility/locks and parent transforms.
- `lib/src/editor/editor_canvas.dart`: camera, pointer ownership and transient previews; completed-edit boundary, grid/direct viewport painter, cached committed paths, selection/movement, anchor zoom, trackpad/scroll/pan, cancellation and disposal guards. No full document copy per pointer move.
- `lib/src/editor/editor_page.dart`: real Editor screen, functional compact wrapping toolbar/colors/widths, session-only status, selection/Delete/Undo/Redo, keyboard and focus ownership.
- `test/board_session_test.dart`:9 tests for immutable snapshots/history/redo branches/revisions/IDs/locks/subtrees/transform/manifest/atomic failure contracts.
- `test/editor_scene_test.dart`:10 tests for geometry, source order, culling, precise hits, filled versus outline shapes, transformed hierarchy, tolerance and±1e9 worlds.
- `test/editor_widget_test.dart`:7 tests exercising actual UI, visible pen pixels, shape tools/backward drags, selection/move/delete/keyboard, camera/cancel, trackpad invalidation and narrow/disposed gestures.
- `test/widget_test.dart`: normal Editor smoke replaces obsolete counter/MyApp assertion; separate BenchmarkApp smoke retained.

Documentation files:

- `AGENTS.md`: explicit latest execution priority and preserved hardening obligations.
- `README.md`: exact verified product launch commands, usable actions, session-loss warning and separate historical lab instructions.
- `docs/EXECUTION_DIRECTIVE.md`: append explicit latest user priority override, preserve original full V1 requirements.
- `docs/MASTER_PLAN.md`:8 concrete MVP-01 checkboxes verified; all250 previous tasks retained; M09 promoted to immediateP0 using tested MVP revision boundary, unresolved stress scheduled in M14.36/258 total checked (13.95%). Full generic command/editor/feature tasks remain unchecked rather than claiming broader scope from the slice.
- `docs/PROJECT_STATUS.md`: current runnable capabilities, actual results, limits and next persistence priority.
- `docs/HANDOFF.md`: exact safe resume actions and protection of current unsaved user boards/dev server.
- `docs/ARCHITECTURE.md`: current entry, pure session/scene and Flutter pointer/render ownership/commit boundaries, full-content limits.
- `docs/DECISIONS.md`: ADR-014 minimal direct editor and reordered execution, no performance guarantee relaxation.
- `docs/TEST_MATRIX.md`: focused commands, actual28+28 results, launches and unqualified native input/platforms.
- `docs/PERFORMANCE.md`: optimization pause, historical evidence preserved, no Debug performance claim.
- `docs/RISKS.md`: session loss, native/logical-key limits, CUA event uncertainty, commit cost and disk pressure.

Evidence created under `benchmark_results/mvp-01/`: compact `verification.json` with exact commands/source hashes/failure exclusions; real `macos-editor.jpg` and `chrome-editor.jpg`; local ignored test/analysis logs, including initial failures. No synthetic screenshot. Native screenshot contains user's existing12 elements; original Chrome46-element board was preserved while isolated agent tab tested pen/rectangle/move/delete/toolbar Undo/Redo/zoom. Do not attribute user drawings to agent testing.

Actual execution: focused **28 host +28 Chrome pass** across4 files; `flutter analyze --no-pub` clean. `flutter run -d macos` built/opened real Editor; CLI detached to retain app. `flutter run -d chrome --web-port=8765 --web-browser-debug-port=9227` built/opened real Editor, server remains available to unsaved tabs. These are Debug functionality checks, no Profile/Release benchmark or release claim. Initial late-up disposed ValueNotifier defect fixed with lifecycle guard/regression; trackpad-start now invalidates cleared draft immediately, covered on both targets. Initial Chrome compiler ENOSPC ran0 cases, excluded; successful retry after~780MiB identified stale project build-output cleanup. SDKs/dependencies/user data and active app/server files untouched. Free disk~0.8GiB.

Limitations: session-only; single selection and root pen/shapes/lines; committed snapshot/index/path rebuilds;100 inverse commands/50K points per stroke; no advanced content/storage/export/mobile qualification. Native framework duplicate-KeyDown assertion happens before app Focus callbacks; no app root cause established, no suppression/SDK change. App logical Latin shortcuts do not qualify non-Latin layouts; live CUA Meta+Z had no undo, toolbar actions verified. Some CUA drags had no commit; input event capture unavailable, no supported toolbar-focus defect. First-drag shapes and keyboard pass synthetic host/Chrome tests; do not claim physical event qualification. Follow up after persistence protects boards.

No package/SDK/pubspec/lockfile/platform/configuration/migration changes in MVP-01. Shared pubspec/fonts and benchmark/render changes from prior sessions remain preserved. No staging/reset/commit; original index checksum unchanged. No engineering continues after checkpoint; launched app/server remain for user's unsaved boards. Next implementation is M09 local save/reopen and failure/recovery/writer correctness, ahead of advanced editing and stress optimization.

## 2026-10-19 — MVP-02 Local Projects, Autosave and Reopening

Implemented durable Boards without event sourcing or a new state-management framework. Independent agents owned codec, platform stores, save coordinator/tests and read-only reviews; coordinator owned Workspace integration/UI/native validation/canonical docs. Preserved old performance work and user changes. Git HEAD advanced externally to c431539 during execution; no agent Git/index/commit writes.

Application/source files:

- `lib/main.dart`: normal entry now owns a WorkspacePage; injectable BoardStore for explicit tests only.
- `lib/src/document/document_codec.dart`: strict schema1 JSON for every existing value/content type, complete manifests/order/hierarchy/metadata, safe finite numbers and geometry; reject unknown/duplicate/future/malformed data and excessive input. No silent schema conversion.
- `lib/src/persistence/board_store.dart`: BoardSnapshot local envelope with validated camera, storage generation and save time; small durable store interface and CAS conflict error. No Undo/resources in storage.
- `lib/src/persistence/file_board_store.dart`: official application-support path, explicit test override, single native workspace writer via process guard+OS lock, serialized compare-and-swap, flushed temp/atomic rename, per-board files and last-board pointer; no destructive destination-delete workaround.
- `lib/src/persistence/web_board_store.dart`: real strict-durability IndexedDB, transaction-complete acknowledgement/CAS, lifetime Web Lock, read-only competitors, connection invalidation and safe close.
- `lib/src/persistence/open_board_store.dart`: conditional backend factory.
- `lib/src/persistence/unsupported_board_store.dart`: actionable unsupported-platform failure rather than a memory fallback.
- `lib/src/persistence/board_autosave.dart`: serialized/coalesced newest snapshot, generations/revision checks, latest acknowledgement status, explicit Retry, retained work, initial read-only ownership and writer-loss failure, disposal-safe accepted drain.
- `lib/src/persistence/close_guard.dart`: conditional close-guard export.
- `lib/src/persistence/close_guard_stub.dart`: native no-op browser warning adapter; native uses lifecycle exit callback.
- `lib/src/persistence/close_guard_web.dart`: beforeunload warning while dirty, listener removal on disposal; no promise of waiting for browser I/O.
- `lib/src/editor/workspace_page.dart`: owns store/open editor/autosave; library create/open, last-board restore, status/errors/retry, settled camera saves, flush and input suppression during switching, candidate validation before replacement, save-aware native exit, safe startup errors and stale-initialization suppression.
- `lib/src/editor/editor_page.dart`: supports externally owned controller, board title/actions; no double disposal; ignores input during async switching.
- `lib/src/editor/editor_canvas.dart`: read-only/input-enabled gates, navigation status/end notification for persisted viewport, preserves all previous drawing behavior and transient commit boundary.
- `macos/Runner/MainFlutterWindow.swift`: native close delegate routes red Close through existing cancelable application termination, retaining visible failed/pending board. Necessary fix discovered by actual fault injection, not speculative platform refactoring.

Tests:

- `test/document_codec_test.dart`:12 exact round-trip/all-content/RTL/strict corruption/safe integer/10,001-element and large-world cases.
- `test/board_snapshot_test.dart`:2 local envelope/camera/generation/invalid-record cases.
- `test/board_autosave_test.dart`:16 serialized writes/coalescing/stale ack/CAS/Undo/camera/failure/retry/lost writer/readonly/disposal/reentrancy cases.
- `test/file_board_store_test.dart`:8 real filesystem/atomic failure/reopen/rapid revisions/independent boards/corruption/close/cross-process lock cases.
- `test/web_board_store_test.dart`:6 actual IndexedDB/Web Locks/reopen/transactions/independent boards/CAS abort/corruption/close cases; no memory backend.
- `test/workspace_widget_test.dart`:12 integrated normal entry/drawing/reopen/Undo/library/rapid edits/status/error/retry/pending switch+keyboard/exit/readonly/writer-loss/startup cleanup/disposed init/viewport scenarios. These controlled store/widget restarts are simulated and not reported as physical crashes.
- `test/support/test_board_store.dart`: explicit test-only delayed/failing store; never selected in production.
- `test/editor_widget_test.dart`: retained7 MVP-01 drawing/geometry/input/disposal regressions using the isolated Editor harness.
- `test/widget_test.dart`: normal persistent entry injects test store and requires acknowledged Saved status; lab smoke retained. Existing BoardSession9 and EditorScene10 tests rerun unchanged.

Dependencies/build files:

- `pubspec.yaml`: pinned official path_provider2.1.6 for host app-data paths and web1.1.1 for modern browser APIs.
- `pubspec.lock`:25 new transitive resolutions; no existing package/Flutter/Dart upgrade. Installed compatibility constraints and exact SDK metadata recorded in verification.
- `macos/Podfile`, `macos/Podfile.lock`: initial Flutter/CocoaPods integration generated by native tooling (CocoaPods1.16.2 already installed; no upgrade).
- `macos/Flutter/Flutter-Debug.xcconfig`, `macos/Flutter/Flutter-Release.xcconfig`: optional generated Pods configuration includes.
- `macos/Runner.xcodeproj/project.pbxproj`, `macos/Runner.xcworkspace/contents.xcworkspacedata`: generated Pods project/framework/check/embed integration. Existing app identity/deployment requirements retained.
- `ios/Podfile`, `ios/Flutter/Debug.xcconfig`, `ios/Flutter/Release.xcconfig`: Flutter's generated initial CocoaPods scaffolding/includes; no iOS build/device claim.
- `linux/flutter/generated_plugins.cmake`, `windows/flutter/generated_plugins.cmake`: generated transitive jni FFI hook declarations; those platforms remain unbuilt/unqualified. No Android/Gradle/SDK version changes.

Canonical/user documentation:

- `AGENTS.md`: current usable-feature priority after verified persistence.
- `README.md`: stable native/web launch commands, exact manual draw/save/close/reopen/library checks and platform durability boundaries.
- `docs/EXECUTION_DIRECTIVE.md`: preserve explicit MVP-02 authorization and automatic next-usable-feature priority.
- `docs/MASTER_PLAN.md`:8 concrete MVP-02 checkboxes verified with evidence; full old tasks preserved; broader storage/hardening work remains unchecked.
- `docs/PROJECT_STATUS.md`, `docs/HANDOFF.md`: actual44/266=16.54% state, safe resume/live apps/data/next text-and-note implementation contracts.
- `docs/ARCHITECTURE.md`: snapshot/store/coordinator/Workspace/resource/close ownership and commit boundaries.
- `docs/DECISIONS.md`: ADR-015 minimal per-platform durable snapshots and ADR-016 evidence-driven native close fix, official package/API references.
- `docs/TEST_MATRIX.md`: actual78 host/76 Chrome, real versus simulated scenarios, commands and exclusions.
- `docs/RISKS.md`: browser profile/eviction, power loss, recovery/device/asset/10K and debug R limitations.
- `docs/PERFORMANCE.md`: no new benchmark/performance claim; previous evidence untouched.
- `docs/DEVELOPMENT_LOG.md`: this exact file manifest and verification record.

Evidence under `benchmark_results/mvp-02/`: `verification.json`, small verified-source archive/hashes, local ignored logs, strict font test preflight audit, raw agent-authored test snapshots/restart checks and real JPEG screenshots. No synthetic screenshots. Normal `flutter run -d macos` and isolated debug app built/ran; real close/relaunch restored bytes. Chrome stable-origin Reload, tab close/reopen, independent1/2-element boards, styles/camera and actual read-only secondary verified. Native permission0555 fault preserved prior ack and in-memory latest;0755+Retry succeeded. Initial red-Close hid failed board; delegate fix repeated failed close/switch blocking and successful saved exit. Controlled pending writes/failures are simulated; native process exit/browser page teardown are real. No full Chrome-process quit (old user tabs preserved), physical crash or power-cut test.

Final source: **78 host+76 Chrome tests pass; analysis clean; Dart format/diff checks clean.** Initial import/finder/invalid-camera-fixture failures preserved and excluded, production range/contract not weakened. Dynamic lost-writer state and async switch keyboard races fixed with regressions. No-authored-work opening failures can exit; disposed opening cannot create a stale board. Native foreground launch warning handled by observing actual window, no SDK suppression. Only generated native caches cleaned; isolated test permissions restored, old Chrome8765 tabs/server preserved. Existing source/history/evidence not discarded.

Development caveat discovered: Flutter web R hot restart retains its prior Web Lock and can open new Dart state read-only. Full browser Reload releases the page lock and restores writing without changing acknowledged IndexedDB data. This is recorded under broader WB-0914; no unsafe lock stealing or private engine hook. Use normal browser profile/stable web-server URL rather than relying on Flutter disposable profile/cache. Undo/tool/selection preferences remain session-only. Portable backups/image original storage/full device/release/10K qualification remain pending.

Next highest-value usable slice inspected: existing M07 text/note domain values and strict codec are ready, but Editor renderer rejects unsupported content and authoritative font manifests must be integrated atomically before exposing tools. Follow-on work requires owned text layouts/readiness, standard Flutter text editing/RTL/IME drafts and persisted reopen tests; no speculative font/raster experiment or new state framework. No new feature implementation is claimed at this checkpoint. No approval question or background engineering claim; live app/server are available for manual testing.

Final data-preservation step: the isolated verification window later showed2 saved elements in its named board. Closed both saved native app processes through their guarded close paths, then ran a one-off Flutter host script outside the automatic test suite, calling existing FileBoardStore APIs under both workspace OS locks. Copied3 absent board IDs into normal workspace as new storage-generation1 snapshots, preserving complete documents/revisions/camera; preflight rejected any conflicting ID. Verified pre-existing normal board raw bytes unchanged and every copied document/camera equal. All source boards retained; normal count4, last “Native named board”2 elements. Reopened the normal app; verification app closed. This is a non-destructive local workspace consolidation for user continuity, not a portable import feature. Result/log: workspace-consolidation.json/log. One extra integrity action passed separately from the78/76 regression counts. Temporary path-specific script was not installed under test/ and cannot run in normal test discovery.

Final Git observation: external staging included current MVP-02 files and separate design/brand assets. This work did not stage/reset/commit or modify those brand files. The earlier empty-index assertion was invalidated by external staging, not a source/test failure; final checks preserve the index as found. Source/archive hashes,78/76 markers, analysis/format and normal workspace-copy integrity were rechecked successfully.
