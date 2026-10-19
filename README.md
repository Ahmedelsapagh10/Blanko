# Whiteboard

Current autonomous execution: [project status](docs/PROJECT_STATUS.md),
[canonical plan](docs/MASTER_PLAN.md), [resume notes](docs/HANDOFF.md).
The historical phase sections below preserve their original evidence; the
[master directive](docs/EXECUTION_DIRECTIVE.md) now authorizes continued local
development. The normal application now opens a persistent Editor with a Board Library.

## Run the persistent Whiteboard

From this repository, launch macOS:

```sh
flutter pub get
flutter run -d macos
```

For Chrome, run a stable local server and open **http://localhost:8766** in your normal Chrome profile:

```sh
flutter run -d web-server --web-port=8766 --web-hostname=localhost
```

Keep the server running while reopening the web app. During development, use a full browser Reload after Flutter hot restart (`R`), which can otherwise retain the old debug-page writer lock. Use the same browser profile and exact URL/port. A normal profile avoids depending on Flutter's disposable debug-browser profile and best-effort profile-cache copying. These commands were executed with Flutter3.41.9/Dart3.11.5. macOS stores boards in its application-support workspace; Chrome uses real IndexedDB. Native and browser workspaces are independent, with no cloud sync.

### Verify saving and reopening

1. Open **Boards**, enter a name and choose **Create board**.
2. Draw with Pen or a shape tool. Select an outline/stroke to move it; try Delete and Undo. Colors and three widths are available.
3. Wait for **Saved locally**. Pan/zoom is also saved after navigation settles.
4. On macOS, close the window or Quit, then reopen the app. In Chrome, reload or close the tab and open the same URL again.
5. Confirm the same board, elements, colors, positions and viewport return. Undo/Redo starts empty because history is session-only.
6. Create a second board with different content; switch between them through **Boards** and repeat reopening. The last selected board reopens automatically.

If **Save failed** appears, keep the board open and use **Retry save** after restoring storage access. Work stays in memory; failed saves block board switching and cancel normal macOS closing. Browser close/reload warns while unsaved, since browsers cannot wait for an asynchronous write during unload. Another editing window/tab holds the writer lock; secondary sessions are explicitly read-only.

**Persistence begins with this version. Older windows still showing “Session only · not saved” are running MVP-01 and cannot retroactively autosave.** The earlier Chrome tabs were left untouched. Do not clear browser site data if you need its local boards. Browser storage can be evicted; portable backups/export remain future work. Forced termination may lose unacknowledged changes; real power-loss/directory-sync recovery is not qualified.

Current scope: Pen, Rectangle, Ellipse, Triangle, Line, single selection/movement/Delete, bounded Undo/Redo, grid/pan/zoom, board creation/library/reopen, automatic acknowledged saves and error retry. Text/notes/images/frames and advanced tools/export follow. Current tool/color/selection preferences are not persisted; authored element styles are. No10K performance pass is claimed.

Actual tests/restart evidence and screenshots: [MVP-02 verification](benchmark_results/mvp-02/verification.json). Exact per-file changes: [development log](docs/DEVELOPMENT_LOG.md#2026-10-19--mvp-02-local-projects-autosave-and-reopening).

## Historical rendering laboratory

The sections below preserve earlier diagnostics and their original gate decisions. Their starter-entry and editor-blocking statements describe historical state and are superseded by MVP-01. The lab remains separate at `lib/benchmark_main.dart`; stress-performance work is deferred to Production Hardening without dropping the10K requirement.

Run the laboratory explicitly:

```sh
flutter run --profile -d macos -t lib/benchmark_main.dart
flutter run --profile -d chrome -t lib/benchmark_main.dart
```

Select a distribution, drag/pinch/scroll to navigate, tap to hit-test, or run the
ten-second pan/zoom sweep. Switch **Pan mode** to **Select / move** to drag an
element. Pointer cancellation, Escape, or loss of application focus cancels the
preview. A completed drag commits one immutable scene change.

**Run Phase 0 suite** measures camera motion and movement in every distribution,
then repeats dense navigation with text/images omitted as diagnostic probes.
Each run has one second of warmup, then ten seconds of camera motion or five
seconds of movement. Results are emitted as `PHASE0_RESULT` JSON lines.

Each scene has exactly 5,000 shapes, 2,500 strokes,
2,000 text/sticky notes, 400 arrows, and 100 image references. The deep hierarchy
adds 64 structural groups. Four generated originals are shared by the image
references: 1024x1024 pixels normally and 2048x2048 for the image-heavy scene.
Decoded pixel counts exclude GPU copies, text, paths, and other application memory.

The runner reports P50/P95/P99 for build, raster, total span, the slower stage,
spatial query CPU time, and paint-recording CPU time, retaining at most 2,400
samples per series. Hit tests use 32 warmup queries and 256 timed queries.
Synthetic update-to-paint timing excludes raster/presentation and hardware input;
it is a diagnostic proxy, not end-to-end input latency. Startup is measured from
Dart entry/scene loading until the first correctly positioned framework frame;
it excludes browser bootstrap and does not establish time to display scanout.
Debug timings are diagnostic only; profile runs on agreed baseline devices are
required before accepting performance budgets. Browser timing availability and
font fallback vary by renderer/environment.

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub --profile --no-web-resources-cdn -t lib/benchmark_main.dart
```

For automatic suites, add `--dart-define=PHASE0_AUTORUN=true` to a profile build.
The native collector samples only its own app's process RSS at 1 Hz, saves JSON,
and closes that app when the suite finishes:

```sh
flutter build macos --no-pub --profile --dart-define=PHASE0_AUTORUN=true -t lib/benchmark_main.dart
python3 tool/run_native_benchmark.py --timeout 240
```

Run targets sequentially, keep viewport size and display scaling fixed, and keep
the app foregrounded. `viewportChanged` and `lifecycleChanges` flag disturbed
runs. The checked-in `benchmark_results/` files and `docs/phase-0-report.md`
record executed measurements and their limitations; they are not release gates.
`tool/start_web_benchmark.js` is a function for an existing Playwright session
(execute it with the browser tool's `filename` argument). It starts the web suite
at `http://127.0.0.1:8765/`; read `window.__phase0` after `complete` becomes true.
Its browser heap snapshots are approximate JavaScript heap usage, not total RAM.

This runner exercises reusable pure Dart affine geometry/camera contracts and a
rebuildable spatial grid against synthetic scenes. Its scene types are benchmark
data, not the portable document schema. The page session owns the immutable
current scene, camera, selection, transient drag, timers, and async job generation.
The renderer owns disposable image/text resources and revision-bound caches.
The spatial grid is rebuildable and updates a committed entry incrementally.
InteractiveViewer handles gestures only. Painting is viewport-sized and subtracts
the camera origin in Dart doubles before sending matrices to the engine, avoiding
the large-coordinate float precision failure demonstrated by a raster regression.
World transforms stay independent of Flutter.
The 2D camera adapter reads the X/Y scale independently of the matrix Z axis;
this is covered by a widget regression for zoom below 1x.
Persistence/recovery, project files, PNG export, real asset import/cache policy,
embedded fonts, production editor tools, and platform release gates remain for
their respective milestones. No package, SDK, Android, or iOS changes are required.


## Phase 0.1 remediation

The remediation report is [docs/phase-0.1-report.md](docs/phase-0.1-report.md).
Phases 1–5 remain blocked: the original rendering/input/memory acceptance gates
have not been approved as passed. The counter entry point is preserved; launch
this lab with `-t lib/benchmark_main.dart`.

`PHASE01_OPTIMIZED=true` (the lab default) enables one bounded composited
raster overview for compact scenes. It contains all original content, with no
text omission or geometry changes. It is used only when minifying that raster;
zooming past its stored resolution restores full vector/paragraph drawing.
There is no retained preview-picture cache: an exploratory version regressed
and was removed. Cache requests share one in-flight build and reject stale
results. After a commit, live drawing remains available; rebuilding the overview
is deferred by 300 ms. That raster rebuild is substantially more expensive than
the synchronous incremental scene update and is reported separately.

Reference and candidate builds use identical fixtures/sweeps and separate files:

```sh
flutter build macos --no-pub --profile --dart-define=PHASE0_AUTORUN=true --dart-define=PHASE01_OPTIMIZED=false --dart-define=PHASE01_DIAGNOSTICS=true --dart-define=PHASE01_AUTORUN_DELAY_MS=10000 -t lib/benchmark_main.dart
python3 -u tool/run_native_benchmark.py --trace --cpu-profile --timeout 300 --output benchmark_results/phase01/macos-before.json
```

Raise the native window during the ten-second delay and keep it visible throughout
the suite. Repeat with `PHASE01_OPTIMIZED=true` and `macos-after.json`. Do not run
another build, correctness suite or rendering target during measurement. The
collector uses the installed SDK's desktop engine environment switches for Dart
CPU sampling; it reads its own local VM service without saving its connection URL.
Default VM ring timelines and 1 ms CPU sampling add overhead to both comparisons.

For the browser, build each variant with the same defines, omitting the native
startup delay, and serve `build/web` on localhost as described above. The isolated
collector uses the already-installed Playwright runtime and Chromium executable;
it does not install either or add a project dependency. On this host:

```sh
/Users/ahmedelsapagh/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node tool/run_web_benchmark.mjs --playwright /Users/ahmedelsapagh/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright --executable "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --hardware-metal --output benchmark_results/phase01/web-before.json --input
```

Repeat with the optimized build and `web-after.json`. Paths above are specific to
this test host; pass an existing runtime/browser on another host. Each suite owns
a fresh headless browser and closes only its own browser. Primary frame runs
have CPU/trace collection disabled. Capture a separate diagnostic with
`--trace-window --stop-after 3 --output benchmark_results/phase01/web-after-diagnostic.json`;
this captures three seconds of dense navigation and streams the trace to gzip.
The collector rejects software GPU compositing by default. Verify the reported
browser version and Metal backend for each comparison. The optional software-input probe runs after frame measurements and
writes a separate `.input.json` file. `tool/start_web_benchmark.js` remains the
shared browser-resident aggregate collector. A full-session trace-export attempt
failed; its recovered frame results are marked exploratory and excluded from the
primary comparison.

Diagnostics add a fixed zoom-out run, 256 timed small commits per strategy after
16 warmup commits, a two-second idle check, and 16 dense/image-heavy open/close
cycles. The full-reconstruction comparison uses the current constructor and full
renderer synchronization; it is not an exact replay of the original Phase 0
constructor. Native stress checkpoints request GC to compare retained Dart heap.
These bounded runs do not prove long-term memory stability or mobile safety.

Pointer instrumentation measures receipt in Flutter until paint recording ends
using one local Stopwatch. It does not subtract browser/native clock epochs and
cannot measure physical input, GPU presentation or scanout. Browser automation is
software input only. No persistence, commands, editing tools or further phase was
implemented.

## Phase 0.2 zoom/cache experiment

See [docs/phase-0.2-report.md](docs/phase-0.2-report.md) for the decision and measured limits.
The tile candidate is opt-in (`PHASE02_TILES=true`); the default lab retains the
Phase 0.1 renderer. No production features, package upgrades or platform changes
are included.

Use `PHASE02_SUITE=true` and `PHASE0_AUTORUN=true` in profile builds. Compare
`PHASE02_TILES=false` (reference) with `true` (candidate). Keep
`PHASE01_OPTIMIZED=true` in both. The new suite has 11 short workloads plus a
three-minute stress run; `PHASE02_SOAK_SECONDS` changes the latter duration, so
use the same value for both variants. It includes a separate moderate-visibility
10K document, directional zoom, threshold oscillation and forced static redraw.
Settled idle, fixed-count commits and 16 renderer open/close cycles are separate
diagnostics. Final Phase 0.2 timing capacity is 12,000 samples, with observed and
retained counts checked explicitly; default Phase 0/0.1 capacity remains 2,400.

```sh
flutter build web --no-pub --profile --no-web-resources-cdn --dart-define=PHASE0_AUTORUN=true --dart-define=PHASE02_SUITE=true --dart-define=PHASE02_TILES=true -t lib/benchmark_main.dart
```

Serve the build locally, then run `tool/run_web_benchmark.mjs` with the installed
runtime/browser paths shown above, `--hardware-metal --memory --input --timeout 600`
and a distinct `--output benchmark_results/phase02/web-after.json`. Build and
collect the reference first. `--memory` requests a final V8 GC/heap snapshot;
it does not measure total browser or GPU memory. CPU tracing stays disabled for
primary suites. For a separate cold zoom diagnostic use
`--trace-window --trace-after normalEditing --stop-after 3 --timeout 120`; its
bounded output is not a completed acceptance suite.

For macOS use the same defines with `flutter build macos --no-pub --profile`,
add `--dart-define=PHASE01_AUTORUN_DELAY_MS=15000`, and collect with:

```sh
python3 -u tool/run_native_benchmark.py --memory --timeout 600 --output benchmark_results/phase02/macos-after.json
```

Keep the native window visible and avoid other rendering/build/test work.
A stopped/occluded native run is incomplete, not a passed gate. `--stop-after`
is for explicitly bounded diagnostics and sets `diagnosticComplete`, not
`complete`. Summarize only fully collected targets:

```sh
python3 tool/summarize_phase02.py --targets web
```

The tile cache owns at most 64 MiB published RGBA plus one in-flight 514×514 image
and temporary engine resources. Fixed scale buckets include zoom and DPR; camera
motion reuses unchanged images. Committed transforms invalidate intersecting
old/new bounds plus the raster gutter, including affected pending work. Source
text, geometry and selection remain authoritative. Missing tiles and active
movement use live drawing. No lower-resolution placeholder or content omission
is introduced. Tail stalls and actual frame cadence must be reviewed alongside
P95 build/raster timings before approving this strategy.

## Phase 0.3 sustained-update audit

See [docs/phase-0.3-report.md](docs/phase-0.3-report.md). Phase 1 remains gated.
No dependencies, SDK versions or platform configuration change.

Use `PHASE03_SUITE=true`, `PHASE0_AUTORUN=true`, `PHASE02_TILES=true` in both
profile builds. Compare `PHASE03_RECOVERY=false` (Phase 0.2 tile strategy) with
`true` (ready tiles plus one combined live draw through missing regions).
Tile caching and recovery remain disabled by default. The rejected smaller-tile
experiment is retained as evidence, not as a runtime strategy.

```sh
flutter build web --no-pub --profile --no-web-resources-cdn --no-wasm-dry-run --dart-define=PHASE0_AUTORUN=true --dart-define=PHASE03_SUITE=true --dart-define=PHASE02_TILES=true --dart-define=PHASE03_RECOVERY=false -t lib/benchmark_main.dart
```

Serve `build/web` on localhost port 8765. Use the existing browser collector and
installed runtime paths above, `--hardware-metal --memory --input --timeout 720`,
and separate outputs `benchmark_results/phase03/web-before.json` and
`web-after.json`. Change only `PHASE03_RECOVERY` between builds. Do not run tests,
builds, another renderer or CPU tracing during timing collection.

The suite adds eight fixed-camera/edit/cold/reload cases before the eleven
historical short workloads and unchanged 180-second stress policy: 20 results
per complete suite. Fixtures remain 10,000 leaves with the original category mix.
New edits commit at most once per animation tick at a nominal 10 Hz; slow runs
coalesce callbacks, so actual operation counts are reported. Single visible,
16 selected and offscreen transforms are separate from continuous navigation.
Cold preparation frames and 3-second cache-population windows have no warmup;
short historical sweeps retain their original one-second warmup. Commit series
include warmup/drain activity; frame series use the measured frame window.

For macOS use the same defines with `flutter build macos --no-pub --profile`,
and `PHASE01_AUTORUN_DELAY_MS=45000`. Raise the native window during that delay
and keep it visible. Collect with `tool/run_native_benchmark.py --timeout 900
--progress-timeout 90 --output benchmark_results/phase03/macos-before.json`.
Repeat for `macos-after.json`. Default collection samples RSS without forced GC
or CPU profiling; `--memory` is an additional intrusive diagnostic. Incomplete
runs cannot qualify a platform. The progress guard terminates only the collector's
own app if benchmark events stop.

```sh
python3 tool/summarize_phase03.py --targets web
```

The validator requires paired profile settings, 20 results, full retained frame
series, bounded cache bytes, no cache errors and zero owned resources after all
16 renderer disposal cycles. Timing series distinguish geometry, synchronization,
index and invalidation CPU costs from engine stages and cadence. Neither engine
vsync intervals nor software input-to-next-paint proxies establish physical
presentation latency, GPU-only time or long-term memory safety.

For the supplemental cold audit add `PHASE03_COLD_AUDIT=true` to those same
profile build commands and use separate `web-cold-before/after.json` and
`macos-cold-before/after.json` outputs. Keep normal suites and this audit separate.
The audit reports four `coldWallAudit` diagnostics (normal/dense, two reloads),
then completes with zero animation-result rows. It measures wall time from the
operation before first dispatch through needed raster readiness and framework
paint completion. It covers opening, first zoom bucket, a visible commit,
forced eviction via distinct empty views, and reconstruction on return.
It includes initial delay that animation-window frame percentiles can miss.
This is a raster-ready/framework proxy, not physical presentation latency.
Validate the completed primary suites and supplemental audits together with:

```sh
python3 tool/summarize_phase03.py --targets web macos --cold
```

The saved macOS primary candidate has lifecycle changes in two windows. Strict
validation intentionally rejects that pair. To inspect the saved diagnostic
results while retaining explicit warnings, use:

```sh
python3 tool/summarize_phase03.py --targets web macos --cold --allow-native-lifecycle-diagnostics
```

That option does not turn the native pair into a clean acceptance result.

## Bounded dirty-region repair experiment

`WB_DIRTY_REPAIR` defaults false. It requires both `PHASE02_TILES=true` and
`PHASE03_RECOVERY=true`. Preserve identical flags/workloads and change only
`WB_DIRTY_REPAIR=false/true` between paired profile builds.

```sh
flutter build web --no-pub --profile --no-web-resources-cdn --no-wasm-dry-run --dart-define=PHASE0_AUTORUN=true --dart-define=PHASE03_SUITE=true --dart-define=PHASE02_TILES=true --dart-define=PHASE03_RECOVERY=true --dart-define=WB_DIRTY_REPAIR=true -t lib/benchmark_main.dart
```

Serve `build/web` on localhost port 8765, then use the existing browser collector
with the installed runtime paths above, `--hardware-metal --stop-after 3 --timeout 120`
and `--output benchmark_results/execution-01/web-repair.json` (reference:
`web-reference.json`). The three six-second editing windows are explicitly bounded
diagnostics, never a completed acceptance suite. Collect/build sequentially.

For native use `flutter build macos --no-pub --profile` with the same defines
and `PHASE01_AUTORUN_DELAY_MS=20000`, raise/check the window before collection,
and run `python3 -u tool/run_native_benchmark.py --stop-after 3 --timeout 160
--progress-timeout 70 --output benchmark_results/execution-01/macos-repair.json`.
No forced GC or CPU profiling is used in these comparisons.

```sh
python3 tool/summarize_dirty_repair.py --target web
python3 tool/summarize_dirty_repair.py --target macos
```

The validator requires profile mode, equivalent workloads/viewports, full received
series, zero recorded lifecycle changes, bounded resident images, zero cache
errors and actual repairs. It always emits `renderingGateQualified=false`.
`repairPixels` counts declared damaged source pixels, not actual output raster
work: every repair still allocates a full 514×514 image. Cold readiness, full
navigation/stress/memory and physical presentation remain separate gates.
The new correctness suite is `test/dirty_tile_repair_test.dart`. No package, SDK,
platform configuration or migration is required.

## Bounded vector-range retention experiment

`WB_RETAINED_RANGES` defaults false. `WB_RETAINED_EXPERIMENT=true` disables tile
and overview preparation in both arms of a direct/vector comparison. Retain
`PHASE01_OPTIMIZED=true` (default); vary only the range flag, false/true:

```sh
flutter build web --no-pub --profile --no-web-resources-cdn --no-wasm-dry-run --dart-define=PHASE0_AUTORUN=true --dart-define=PHASE03_SUITE=true --dart-define=PHASE02_TILES=false --dart-define=WB_RETAINED_EXPERIMENT=true --dart-define=WB_RETAINED_RANGES=true -t lib/benchmark_main.dart
```

Serve and collect as above with `--stop-after 3`, writing distinct
`benchmark_results/execution-02/web-direct.json` / `web-retained.json`.
For macOS use `flutter build macos --no-pub --profile` with identical defines
plus `PHASE01_AUTORUN_DELAY_MS=20000`, raise/visually check during the delay,
and collect `macos-direct.json` / `macos-retained.json` with the existing native
collector. Build and collect serially; do not run tests during frame collection.

```sh
python3 tool/summarize_retained_ranges.py --target web
python3 tool/summarize_retained_ranges.py --target macos
```

The validator checks actual commits and 1/16 active/resolved/synchronized entries,
profile flags/platform, matched viewport/IDs/assets, all received timing samples,
recorded lifecycle/focus controls and bounded picture estimates. It always emits
`renderingGateQualified=false`. Picture bytes exclude referenced resources and
engine memory. First-use CPU recording clocks exclude presentation and cold app
load. This draws ordered vector pictures in one painter; independent on-screen
raster-cache layers are not implemented. See `docs/PERFORMANCE.md`; do not use
tile-specific `PHASE03_COLD_AUDIT` to qualify this path. Correctness coverage:
`test/retained_ranges_test.dart`; pure production contracts:
`test/document_model_test.dart`. No dependency/platform/migration changes.

### Bounded on-screen layer diagnostic (execution-03)

`WB_RETAINED_LAYERS=true` selects the opt-in composited canvas and ordered static
layer runs around live edits. It is separate from `WB_RETAINED_RANGES`; enabling
both is rejected. Defaults remain off. Caps:33 static subtrees,16MiB approximate
pictures and64MiB estimated raster exposure. The estimate is not total GPU memory.
Camera/membership changes rebuild; complete direct fallback preserves content
when fragmentation or resource limits prevent retention.

For the matched four-row diagnostic, use the execution-02 profile command above
with `WB_RETAINED_EXPERIMENT=true`, `PHASE02_TILES=false`,
`WB_LAYER_INTERLEAVED=true` and explicit per-arm flags:

- Direct: `WB_RETAINED_RANGES=false`, `WB_RETAINED_LAYERS=false`.
- Vector: `WB_RETAINED_RANGES=true`, `WB_RETAINED_LAYERS=false`.
- Layers: `WB_RETAINED_RANGES=false`, `WB_RETAINED_LAYERS=true`.

Build each arm serially from the same sources and collect with `--stop-after 4`.
Native builds also require `PHASE01_AUTORUN_DELAY_MS=20000`; raise and verify the
window before the suite starts. The fourth row spreads16 edited entries across
visible paint order, exposing fragmented retention rather than an active prefix.
Save as `benchmark_results/execution-03/{web,macos}-{direct,vector,layers}.json`.

```sh
python3 tool/summarize_layers.py --target web --interleaved
python3 tool/summarize_layers.py --target macos --interleaved --dense-only
```

The recorded macOS baseline has a normal-row lifecycle change; `--dense-only`
explicitly excludes every arm's normal row and validates only the three dense
rows. Omit this option for a fresh complete controlled four-row comparison.

Validation checks modes, density/active IDs/paint indices, GPU environment,
received distributions, actual commit widths, ownership estimates and retained
subtree submissions. Interleaved full fallback is explicitly reported as a
limitation. Bounded diagnostics cannot qualify the full rendering gate.
Correctness suites: `test/retained_layers_test.dart` and
`test/document_settings_test.dart`. `tool/run_test_batches.py` runs the complete
suite in fresh sequential file processes when compiler lifetime/space is a
constraint; requires successful markers and unchanged source hashes. Tests are
not production performance measurements.

### Observed web backend diagnostic (execution-04)

This compares the existing vector path; it does not adopt WebAssembly or change
production hosting. Use the execution-03 four-row defines, with
`WB_RETAINED_RANGES=true`, `WB_RETAINED_LAYERS=false`.

- CanvasKit build: `--profile --no-web-resources-cdn --no-wasm-dry-run`.
- Both skwasm builds: `--profile --no-web-resources-cdn --wasm`.
- Serve CanvasKit and skwasm-multi with `python3 tool/serve_benchmark.py --isolated`.
- Serve skwasm-single with `python3 tool/serve_benchmark.py`.

The server binds only127.0.0.1:8765 and serves build/web. Start each fresh browser
with the existing collector command, `--stop-after 4` and
`--expect-backend canvaskit`, `skwasm-single` or `skwasm-multi`; save as
`benchmark_results/execution-04/web-{variant}-vector.json`. Use the existing
bundled Playwright path/executable arguments above; no project dependency added.
Stop your server before switching variants. Compiler reports and actual engine
exports/requests/headers/workers must agree; a build flag alone is insufficient.
Private diagnostic probes are verified only against installed Flutter3.41.9.

```sh
python3 tool/summarize_web_backends.py
```

Recorded profiles reject backend promotion. Wasm widget-test suites did not load
any case and must not be reported as passed. `tool/inspect_web_startup.mjs` is a
separate bounded fresh-browser request diagnostic using the same runtime args,
not a performance gate. It exposed external font fallback still pending at first
READY; controlled licensed font assets/readiness are next. See PERFORMANCE and
ADR-012 for the63s outlier, partial evidence and provenance limits. No SDK/package
upgrade or production bootstrap/header change.

### Controlled benchmark fonts

The laboratory uses pinned, unmodified Roboto3.015 and NotoSansArabic2.012 files under `assets/benchmark_fonts/`, with OFL notices, upstream release/archive/file hashes and corpus coverage. These are benchmark choices; the production font policy remains pending. Shared `pubspec.yaml` declares local default Roboto to prevent the web engine's automatic external default-font request. The laboratory additionally awaits its explicit font aliases before creating the theme/scene. READY records font preparation/readiness; load failure shows Retry and cannot start a run. No dependency or SDK upgrade is required.

Before direct Chrome test commands, generate the ignored copies served by Flutter's browser test runner:

```sh
python3 tool/verify_benchmark_fonts.py --prepare-web-tests
flutter test --no-pub --platform chrome test/benchmark_fonts_test.dart
```

`tool/run_test_batches.py` performs this preflight automatically for serial verification. The test-only asset bridge preserves genuine custom fonts instead of Ahem; download fallback is disabled in these tests. Regenerate fixtures after checkout or cleanup. Host tests read the original bundled files.

For new controlled Profile diagnostics, `tool/run_font_profiles.py --help` describes the installed Node/Playwright/Chrome paths to supply. It captures serial direct/vector/layer arms and checks local font transfers before READY; external-blocked startup is a separate diagnostic. It does not qualify the complete rendering gate. Text-bearing tile scenes at nonbucket display scales take a reported complete direct fallback to preserve small glyphs and paint order. Matching scales with fractional camera/widget/device offsets remain unqualified. Historical unpinned/Ahem metrics remain separate evidence.
