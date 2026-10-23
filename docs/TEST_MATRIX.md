# Test matrix

Updated 2026-10-23. Complete requirement/task mapping: [MASTER_PLAN](MASTER_PLAN.md), per-milestone verification contracts. This matrix records current coverage rather than claiming future tests exist.

## Windows Release correction — 2026-10-24

`tool/verify_windows_release.ps1` is deliberately restricted to a fresh Windows GitHub runner. It builds `integration_test/windows_release_test.dart` as actual Release/AOT with self-reported fail-closed results, launches separate write/read processes using the normal default Board store, verifies Files/PNG controls and exact acknowledged document/camera/original assets after process exit, then rebuilds normal `lib/main.dart` and compares its actual embedded icon. Run40042010681 passed both phases and19focused Windows file/storage checks. No mocked store/channel. Native chooser interaction itself is not automated. First attempts exposed a test-only KeyEventSimulator debug-name lookup absent in Release; pointer-based dialog interaction avoids it without modifying application behavior. `flutter drive --release` for native desktop is unsupported by this SDK, so do not relabel Debug/Profile as Release.

## Native platform verification — 2026-10-23

Four real-engine integration cases passed on Windows, Linux (Xvfb), macOS, Android emulator and iOS simulator. Actual providers/channels, isolated durable stores, editor gestures/Undo, original assets, portable files and PNG pixels are exercised. Automated store reopening is not a process restart. Current evidence, sources, real UI/process restarts and remaining hardware/provider limits: `releases/native-platform-verification.json`.

```sh
flutter test --no-pub integration_test/platform_smoke_test.dart -d windows
xvfb-run -a flutter test --no-pub integration_test/platform_smoke_test.dart -d linux
flutter test --no-pub integration_test/platform_smoke_test.dart -d macos
flutter test --no-pub integration_test/platform_smoke_test.dart -d <disposable-android-device-id>
flutter test --no-pub integration_test/platform_smoke_test.dart -d <ios-simulator-id>
bash tool/test_android_signature.sh
```

Use a fresh disposable Android AVD for Debug integration tests, before installing the owner-signed Release APK. Their signing keys differ; never let a test installation uninstall an existing app holding user Boards. CI uses isolated fresh devices. Actual Android Release checks separately cover drawing, Undo/Redo, acknowledged save/process restart, Downloads-provider PNG/project output/import and imported-image restart. Actual411×706 PNG passes signature/chunk CRC/dimension checks and visual inspection; actual `.wboard` passes the production decoder. Other providers and physical-device qualification remain open.

Desktop Release startup is checked before packaging; Android owner certificate must match `android/release-certificate.sha256`. Fourteen fast guard cases cover accepted SDK labels and rejected unapproved/additional signers, source-stamp substitution, missing output and verifier errors. The minimal `tool/test_android_signature_real.sh` creates only a disposable fixture key/APK, checks the installed SDK tool and requires a real verification marker; local SDK36.0.0 passed, hosted SDK37 regression verification passed in40018755569 and again before the published beta.3 build in40019361470. It does not use owner signing credentials or publish files.

Do not add `--no-pub` to Android Release builds immediately following native Debug tests: Flutter3.41.9 must regenerate plugin registration for Release. Normal `flutter build apk --release` is verified; stale IntegrationTestPlugin registration previously caused a genuine build failure.

## MVP-02 persistence verification — 2026-10-19

**78 host +76 Chrome pass**,9 files per target, static analysis clean. Exact commands/source hashes/archive/failure exclusions in `benchmark_results/mvp-02/verification.json`. Codec12, snapshot2, autosave16, workspace12, entries2, Editor7, BoardSession9, EditorScene10; native backend8 versus browser backend6. These include all MVP-01 regressions; historical rendering suites were not rerun.

Native tests use real temporary files, flushed reopen, cross-process OS locks, CAS/rapid generations, actual rename failure/retry, malformed data and pending-close drain. Chrome backend tests use actual IndexedDB/Web Locks, transaction completion and aborted stale CAS, independent boards and connection reopen. Test doubles are explicitly injected in UI/coordinator tests only; production has no memory fallback.

Actual normal macOS entry and separate isolated bundle were built and relaunched in new processes. Normal1-stroke snapshot and isolated3-board snapshots were byte-identical after restart. Native live permission0555 fault produced Save failed while retaining memory and prior acknowledged bytes; restore0755/Retry saved latest. Failed red Close initially hid the window; fixed native delegate, then repeated failed close retained visible board and blocked switch; saved close exited normally. Screenshots and restart JSON are retained. Permissions restored; no user-data cleanup.

Actual Chrome page Reload, close-tab/fresh-tab reopening, independent styled boards, last-board/80% viewport restore and real second-tab read-only verified. Entire Chrome process was not quit because earlier tabs contain unsaved MVP-01 work. Simulated pending-I/O/widget restarts are labeled; no actual crash/power-cut claim. Final Debug builds prove functionality only. Native launcher foreground warning was resolved by selecting the running window through CUA; no claim of universally clean OS launch behavior.

Development-only finding: Flutter `R` hot restart can leave its old Web Lock promise alive; use a full browser Reload after restart. No unsafe lock stealing or private SDK hook adopted. Browser reload/tab lifecycle is qualified; debug hot-restart cleanup remains part of the broader unverified writer-coordination task.

Commands are in README/HANDOFF; Chrome test preflight emits its audit under mvp-02 so historical asset evidence is not overwritten. Windows/Edge/Safari/Android/iOS, physical input/presentation, long memory and10K save/render costs remain unqualified.

## MVP-01 editor verification — historical checkpoint (2026-10-19)

28/28 host and28/28 Chrome tests across `editor_widget_test.dart` (7), `widget_test.dart` (2), `board_session_test.dart` (9), `editor_scene_test.dart` (10). `flutter analyze --no-pub`: no issues. Exact commands/exit codes/source hashes and preserved initial failures: `benchmark_results/mvp-01/verification.json`. These are focused integration/regression tests, not a rerun of every historical renderer suite or a performance claim.

Coverage: real normal entry, lab smoke preserved, visible pen pixels and immutable previews, all four shapes/backward drag, topmost/precise hits and viewport culling, parent transforms/locks/order, transactional revisions and bounded undo/redo, selection/move/delete/keyboard, pan/anchor zoom, Escape/cancel, trackpad-start invalidation, narrow layout, safe disposal with a live pointer. An initial real disposed-notifier failure was fixed and retained in evidence; the Chrome ENOSPC attempt ran zero tests and is excluded.

Actual `flutter run -d macos` and `flutter run -d chrome --web-port=8765 --web-browser-debug-port=9227` built/opened the real Editor. Screenshots under mvp-01 are actual running apps. Chrome isolated live checks verified visible pen/rectangle/movement/Backspace/toolbar Undo/Redo and zoom. Existing user boards preserved. Native duplicate-KeyDown framework warning and live non-Latin/CUA shortcut/drag limitations remain recorded; this is not complete native hardware/focus/layout qualification. Windows/Edge/Safari/Android/iOS device and Profile/Release editor checks remain unchecked long-term tasks.

Focused commands:

```sh
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 test/editor_widget_test.dart test/widget_test.dart test/board_session_test.dart test/editor_scene_test.dart
python3 tool/verify_benchmark_fonts.py --prepare-web-tests
CHROME_EXECUTABLE='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' flutter test --no-pub --platform chrome test/editor_widget_test.dart test/widget_test.dart test/board_session_test.dart test/editor_scene_test.dart
```

## Baseline commands

Use installed Flutter 3.41.9 / Dart 3.11.5; no upgrades. `flutter analyze`; `flutter test --no-pub`; `CHROME_EXECUTABLE='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' flutter test --no-pub --platform chrome`. Run focused renderer tests first for cache changes. Correctness test timing is not production performance. SDK cache stamp writes may require the environment's execution approval.

Geometry/camera: `geometry_camera_test.dart`; spatial index: `spatial_grid_test.dart`; scene/hierarchy/deltas/fixture: `benchmark_scene_test.dart`, `incremental_scene_test.dart`; renderer/hit/ownership: `scene_renderer_test.dart`, `render_cache_test.dart`; tile alpha/RTL/gutter/races: `tile_cache_test.dart`, `recovery_cache_test.dart`, `dirty_tile_repair_test.dart`; page/input cancellation: `benchmark_page_test.dart`; editor+lab entry points: `widget_test.dart`.

Historical latest: 53 host + 53 Chrome tests and clean analysis in `benchmark_results/phase03/validation.json`. Execution 01: **61 host + 61 Chrome pass**, eight new repair cases, final analysis clean; `benchmark_results/execution-01/verification.json` records initial real pixel failure, compiler ENOSPC and verified rectangular-exclusion fix.

## Performance and lifecycle

Reproduction: README and `tool/run_web_benchmark.mjs`, `tool/run_native_benchmark.py`, `tool/summarize_phase03.py`. Use profile/release only; retain raw stages, all received counts, viewport/lifecycle controls and exact flags. Existing paired summary is clean for Chrome, diagnostic-only for two native windows. `--allow-native-lifecycle-diagnostics` never converts those rows into passing qualification.

Physical input/presentation, driver memory return, long duration editor lifecycle, imported asset pressure, context loss and supported baseline devices remain pending. Dirty repair now has verified host/Chrome direct/mixed/repaired pixels, old-pixel erasure, alpha/order/fractional RTL/large-world, pending-revision, fallback, failure/retry and disposal tests. Whole-image allocation and other device fidelity/performance remain unqualified.

## Platform coverage

macOS and Chrome: historical profile suites executed; full V1 runtime unimplemented. Current toolchain discovery recorded separately. Windows unavailable on this macOS host. Edge absent in prior discovery; Safari present but unqualified. Android SDK and iOS toolchain presence require device/build confirmation; no mobile runtime is inferred. M13 tracks each mandatory platform and M15 signing/account validation separately.

Production commands/history/tools/selection/text/images/frames/storage/project/export/UI/security/CI gates: pending implementation and relevant per-task verification; no coverage credit from synthetic rendered content.

## Execution 02 — final scoped verification

**90 host + 90 Chrome tests pass; final analysis clean**. Nine retained graphics cases test source-order alpha/preview/cancel/commit, inactive/group invalidation even after direct paint, camera membership, fractional RTL/images/±1e9, omission fallback, LRU/bytes/overflow/span and disposal. Eleven production model cases test immutable content/IDs/order, owning vs export frames, cycles/orphans, invalid values, safe revisions and general opacity. Nine geometry cases test independent/manual/200 seeded affine routes, ±1e9 at 1e−5 tolerance, overflow/underflow, missing IDs, 5,000-deep resolution and immutable snapshot ownership. Models/geometry are independent contracts, not editor integration.

Additional retained-flag configuration: `flutter test --no-pub --dart-define=WB_RETAINED_RANGES=true --dart-define=WB_RETAINED_EXPERIMENT=true test/document_model_test.dart test/benchmark_page_test.dart` passed 14 host and 14 Chrome (add existing Chrome target/environment flags). These are repeated configurations, not extra unique tests. Geometry focused host nine passed, then full regressions included it on both targets. Logs/results/source hashes: `benchmark_results/execution-02/verification.json`. All frame collections ended before these checks; no test timing is a production result.

Two strict direct/vector profile pairs, three rows each arm, with recorded first-use CPU clocks and estimates; all summaries explicitly remain unqualified. Native wrong-delay capture excluded. Six malformed artifacts (no commits/active IDs, collector failure, wrong platform, focus change, wrong resolved count) rejected by the validator; original reports unchanged. Summarizer syntax compiles using a writable temporary Python cache. Python's default external cache path was sandbox-denied; no source change required. Chrome full suite completed 90 despite a slow pressure observation, before any guarded stop matched a process; no test was terminated or retried.

No new cold/navigation/all-visible stress/long-soak/physical input or other mandatory-platform evidence. WB-0119 remains partial and WB-0114 unresolved. Document metadata/settings/manifests and visual bounds/hits/index/reparent/commands/persistence remain pending.

## Execution03 verification

Full current renderer/model regression:109 host +109 Chrome tests across16 files per target, run serially with `python3 tool/run_test_batches.py --output benchmark_results/execution-03/recovered-tests/host-batches.json` and the same command with `--platform chrome` and Chrome output path. Each file gets a fresh compiler process; JSON requires exit0, explicit success marker and unchanged source hashes. All-in-one/first batched host attempts failed with actual ENOSPC and are preserved, not counted as passes. See execution-03/verification.json.

After those runs, benchmark-only optional interleaved workload/paint-index reporting and page test lookup were changed. Three affected page cases passed on each target with `flutter test --no-pub --concurrency=1 --dart-define=WB_RETAINED_LAYERS=true --dart-define=WB_RETAINED_EXPERIMENT=true --dart-define=WB_LAYER_INTERLEAVED=true test/benchmark_page_test.dart` (add `--platform chrome` for Chrome). Final braces-only test lint repair followed; `flutter analyze --no-pub` reports no issues. Debug test timings are correctness evidence only.

New graphics10 cases cover retained engine submissions, strict pixel parity, offsets/clipping/fractional scale/DPR/alpha/order/RTL/images/large-world/group edits, cancellation/commit/inactive invalidation, detach/replacement/disposal, complete budget fallback and recording-failure cleanup/retry. New document settings9 cases cover immutable/default/legacy declarations, resource uniqueness/references, image dimensions/MIME/digest bounds, workspace IDs and metadata chronology/versions. No dependency/platform configuration changes.

## Execution04 backend verification

`flutter test --no-pub --concurrency=1 test/benchmark_page_test.dart` and same with `--platform chrome`:3 cases each pass; `flutter analyze --no-pub`: clean. Dart change is compiler metadata only; renderer/document unchanged. Full109/109 suite not rerun.

`flutter test --no-pub --concurrency=1 --platform chrome --wasm test/retained_ranges_test.dart test/retained_layers_test.dart test/benchmark_page_test.dart`:3 suites fail to load,0 cases executed. Pure geometry `--wasm --verbose` diagnostic with explicit Chrome also never loaded a case; owned process interrupted after608s. SDK exit0+'No tests ran' is STOPPED, never PASS. No SDK upgrade/edits. Logs and exact stop proof in execution04.

`python3 tool/summarize_web_backends.py`: actual3-arm/4-row profile evidence passes compiler/backend/thread/worker/header/resource/complete-sample/commit/control/density checks;12 negative fixtures rejected. This is diagnostic validation, not a performance acceptance pass. Separate bounded startup request trace succeeds but does not reproduce63s outlier; exposes pending external Arabic font fallback at READY. No font-readiness guarantee or physical/cold/long-memory qualification.

Execution05 font controls: run `python3 tool/verify_benchmark_fonts.py --prepare-web-tests` before direct Chrome test commands; batch runner now audits/copies automatically. Generated `test/benchmark_font_assets/` is ignored and can be regenerated. Test-only AssetManager bridge exists because installed web test environment ignores platform messages and otherwise forces Ahem; explicit fonts enabled, fallback downloads disabled. No SDK modification. Asset audit establishes fixed bytes/OFL/version/weight/cmap/GSUB/GPOS presence, not Arabic shaping or arbitrary Unicode.

Initial retry error/lint and interrupted Chrome asset waits, host warm-glyph mismatch, and old-completed-future widget wait are preserved under execution05; no incomplete run counts as PASS. Fractional tile fallback assertions retain original limits and add exact pixel equality and observed fallback. Cache preparation/repair still tested, while aligned cases separately prove actual cache painting. Physical input, other devices/browsers and complete shaping/IME coverage remain separate pending obligations. Final counts/evidence are recorded in execution05/verification.json when complete.

Final execution05: **116/116 host and116/116 Chrome**,17 files each, identical source/asset hash sets and complete markers (`host-tests.json`, `chrome-tests.json`); analysis no issues,10 changed Dart files format clean. Actual12 Profile rows,2,911 frames and617 commits independently recomputed;18 malformed profile/font/control/provenance/startup/cap cases rejected, in addition to4 asset/license/coverage cases. Independent validator `python3 tool/validate_font_profiles.py` currently also checks retained final build/web bytes; a later build/cleanup will invalidate that local-byte recheck. Historical runner hashes/raw samples remain preserved; rebuild and recapture for new sources. External-blocked fresh startup and all four font requests-before-READY verified. Full engine/presentation/input/memory/platform gate remains NO-GO/unqualified.
