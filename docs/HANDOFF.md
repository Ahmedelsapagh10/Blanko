# Handoff

Updated2026-10-19. Resume AGENTS → PROJECT_STATUS → MASTER_PLAN → Git/relevant sources/tests. Latest user priority: **usable editor first, then local saving/reopening; speculative cache/font/stress optimization paused.** Ordinary fixes and independent subagents authorized. No next-phase approval needed.

## Current checkpoint

**MVP-01:8/8 session-scope deliverables verified. Overall36/258 =13.95%.** Prior250 tasks all preserved; no full V1/platform/performance gate claimed. Main now launches `WhiteboardApp`/`EditorPage`; separate `benchmark_main.dart` laboratory unchanged by this MVP. Pen/four shapes, single selection/move/delete, bounded inverse Undo/Redo, toolbar/colors/widths, grid and camera work with production documents. Persistence/text/images/frames/advanced tools/export remain absent.

## Protect current unsaved user boards

Native app remains open after CLI detach; screenshot at mvp-01/macos-editor.jpg shows12 user-created elements. Original Chrome tab atlocalhost:8765 had46 user elements and is untouched; agent used a separate test tab with3 elements. Chrome dev server from `flutter run -d chrome --web-port=8765 --web-browser-debug-port=9227` remains running (tool session9471), supporting unsaved sessions. Do not close/reload/restart these apps/server as routine cleanup. App explicitly says “Session only · not saved.” These boards are not durable; a new launch starts empty. No background engineering continues after checkpoint.

## Source ownership

- `lib/main.dart`: normal app/theme/editor entry, no BenchmarkApp.
- `src/editor/board_session.dart`: pure immutable production BoardDocument session, ID allocator,100-entry sparse inverse deltas; add/move/subtree delete/undo/redo, monotonic revisions/atomic failures/inherited locks.
- `editor_scene.dart`: existing DocumentGeometry+SpatialGrid resolution/culling, reverse precise hits; no Flutter resources.
- `editor_canvas.dart`: controller owns camera, selection and local pointer draft; mutable path/point preview never reconstructs document per move. Commit once at pointer-up, rebuild derived index/paths per commit. Direct painter renders supported root pen/shapes/lines with camera-relative transforms/grid; no experimental caches or async resources.50K points/stroke, world±1e9, camera0.02–32. Tool/cancel/Escape/focus/dispose guards.
- `editor_page.dart`: owns/disposes focus/controller, minimal toolbar and logical-key shortcuts. Text/image/frame rendering and hierarchy-opacity integration not exposed; no importer.

## Actual verification

`benchmark_results/mvp-01/verification.json` records source hashes, exact commands,28 host+28 Chrome cases across4 test files, clean analysis, actual Debug launch screenshots and all limitations. New tests: board_session9, editor_scene10, editor_widget7; widget_test2 covers Editor and separate BenchmarkApp. Chrome font preflight uses existing fixed assets/generated ignored copies; no font experiment or new package. No full historical renderer-suite rerun and no new benchmark.

Initial widget test caught late pointer-up notifying disposed toolbar ValueNotifier; fixed with disposal/gesture guard and regression. Trackpad-start draft invalidation fixed/tested. Initial Chrome compiler ENOSPC ran0 tests, preserved as editor-chrome-no-space.log; retry28 passed. `*.log` files are ignored/local; durable summary JSON contains outcomes/exclusions. Only6 Oct18 flutter_build directories, stale macOS Profile product/module/SDK caches removed (~780MiB); current Oct19 hash301a953dd6bf068b6762774d7d72c7fb, native Debug, active Chrome files and all user data preserved. Free space~0.8GiB; avoid parallel heavy builds.

Native Debug launch emits duplicate-KeyDown Flutter HardwareKeyboard assertion before application callbacks (physical comma0x70036/logical Arabic waw0x648). Exact cause/layout involvement unproved. Read-only audit found no app injection/reset and standard native template. Do not suppress assertions/clearState/patch or upgrade SDK. Open Flutter issue125975 describes startup state races, not proof of this exact cause. Non-Latin logical shortcuts are not handled by current Latin logical-key matching; live CUA Meta+Z did not undo, toolbar Undo/Redo verified. Some native CUA Chrome drags did not commit; event arrival/cancel evidence unavailable. SDK Focus.hasFocus includes descendants, so no supported toolbar→canvas cancellation diagnosis. Immediate first-drag shape/widget regressions pass both targets. Full physical input/native focus/layout remains separate unchecked work.

## Exact next actions

1. Inspect Git/index/capacity safely. Preserve original index SHA256 b197c24fb16b37a8c120b9709e75474942f021b2a754a0ce4e783fe02b65130a; no blanket add/reset/commit. Docs/source changes are intentional on top of large original staged/mixed work. Main/README/widget test are now product-facing.
2. Start M09P0 local save/reopen (WB-0901–0907,0911,0913–0918 as relevant). Reuse existing BoardDocument immutable types and BoardSession revision boundary; storage does not wait for full generic M03/advanced editing. Inspect existing document contracts before selecting minimal versioned serialization, platform storage and writer ownership. Verify official compatibility before any demonstrated-necessary dependency; no new package by default. Test strict malformed/unsupported content rejection, deterministic round trips and authoritative manifests before writes. Never silently lose content.
3. Integrate ordered autosave only after completed commits, honest latest-acknowledged Saving/Saved/Error status, recovery/error UI and board create/reopen. Keep pointer drafts unsaved. Cover stale completion/retry/permission/quota/crash, atomic writes/transactions, single writer/read-only secondary and actual macOS+Chrome reload/reopen. Preserve current unsaved sessions during development; don't assume hot restart retains them.
4. Fix/qualify shortcuts across non-Latin logical layouts with targeted tests and actual event evidence after persistence protects boards. Keep working toolbar and current focus cancellation. No speculative fix for CUA drag symptoms without reproduction.
5. Continue text/notes/images/frames, remaining tools, project+PNG export, adaptive mobile, then all mandatory device/release/performance hardening. Keep normal entry runnable after each slice. No cache/font experiments first.

## Reproduction commands

```sh
flutter run -d macos
flutter run -d chrome --web-port=8765 --web-browser-debug-port=9227
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 test/editor_widget_test.dart test/widget_test.dart test/board_session_test.dart test/editor_scene_test.dart
python3 tool/verify_benchmark_fonts.py --prepare-web-tests
CHROME_EXECUTABLE='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' flutter test --no-pub --platform chrome test/editor_widget_test.dart test/widget_test.dart test/board_session_test.dart test/editor_scene_test.dart
```

Use current open localhost session if occupied; avoid reloading unsaved boards. Flutter3.41.9/Dart3.11.5/M4/16GiB/macOS26.5.1/Chrome155.0.8059.82, no upgrade/migration/configuration step.

## Historical performance

All prior reports, assets, code and evidence retained. execution05 genuine-font116/116 correctness and12 hardware Profile diagnostic rows remain historical; dense25–34ms still exceeds16.7ms, no cache promotion. New builds/cleanup replace final build bytes, so old validator's retained-build recheck is no longer applicable; runner hashes/raw samples/source archive remain evidence.10K all-visible, physical input/presentation, long-memory, Windows/Edge/Safari/mobile/signing remain unverified. Do not replay failed benchmarks before earlier-priority product features. Full file list/changes in DEVELOPMENT_LOG.
