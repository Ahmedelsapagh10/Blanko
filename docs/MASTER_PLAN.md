# Master execution plan

Canonical backlog and acceptance: [execution directive](EXECUTION_DIRECTIVE.md). Updated 2026-10-19. Every task inherits its named milestone acceptance and verification contracts. P0 = correctness/critical path; P1 = required V1; P2 = finishing/release. Dependencies are prerequisites; integration additionally requires relevant feature gates. Check only verified work.

Priority override2026-10-19: MVP-01 and MVP-02 usable editor/persistence are verified; MVP-03A and MVP-03B are verified; current priority is the dedicated M12 UI/UX transformation. Preserve rendering evidence and the10,000-element requirement; unresolved stress performance moves to M14 Production Hardening and does not block the usable editor. Correctness, crash safety and reasonable interaction remain mandatory. Speculative caching/fonts/repeated benchmark investigations paused. This explicit user priority supersedes historical rendering prerequisites for editor integration.

UI/UX checkpoint 2026-10-20: M12 presentation implementation verified on available desktop/browser targets. Native phone/tablet runs, full assistive-technology review and M13 device/input qualification remain unchecked. No claim of full V1 or 10K performance acceptance. See `benchmark_results/ui-ux/verification.json` and `docs/HANDOFF.md`.

## MVP-03A — Eraser & Clear All (verified)

Priority P0; depends on MVP-02. Acceptance: real-editor gestures are atomic, cancel-safe, zoom-aware, undoable and persisted. Verification: focused command/geometry/widget tests, analysis and macOS/Chrome smoke checks. Extreme performance remains in M14.

- [x] MVP-0301 Object eraser with continuous drag and one Undo operation.
  - Status: VERIFIED; priority: P0; dependencies: MVP-02.
  - Acceptance: Object eraser with continuous drag, atomic stroke deletion, zoom-aware hit testing and one Undo operation; tests: `test/stroke_eraser_test.dart`, `test/editor_eraser_test.dart`; evidence: passing on host and Chrome web.

- [x] MVP-0302 Adjustable screen-space eraser size and visible cursor.
  - Status: VERIFIED; priority: P0; dependencies: MVP-02.
  - Acceptance: Adjustable screen-space eraser size slider in toolbar and visible cursor rendered via canvas painter; tests: `test/editor_eraser_test.dart`; evidence: passing on host and Chrome web.

- [x] MVP-0303 Segment eraser preserves stroke fragments, style, transforms and order.
  - Status: VERIFIED; priority: P0; dependencies: MVP-02.
  - Acceptance: Segment eraser splits strokes into fragments at intersections, preserving style, opacity, transform and document order; tests: `test/stroke_eraser_test.dart`, `test/editor_eraser_test.dart`, `test/board_session_test.dart`; evidence: passing on host and Chrome web.

- [x] MVP-0304 Confirm/cancel Clear All, one Undo, current-board identity preserved.
  - Status: VERIFIED; priority: P0; dependencies: MVP-02.
  - Acceptance: Confirmation dialog for Clear All with cancel safety, single undo restoration, and current board id/title preservation; tests: `test/editor_eraser_test.dart`; evidence: passing on host and Chrome web.

- [x] MVP-0305 Verify autosave/reopening and actual macOS/Chrome tools.
  - Status: VERIFIED; priority: P0; dependencies: MVP-02.
  - Acceptance: Erased content, clear all, and undo/redo persist to durable storage and survive workspace reopening across macOS and Chrome; tests: `test/editor_eraser_test.dart`, `test/workspace_widget_test.dart`; evidence: passing on host and Chrome web.

## MVP-03B — Text Editing & Sticky Notes (verified)

Priority P0; depends on MVP-03A. Acceptance: multiline Arabic/English editing, colors, size, wrapping, select/move/resize/delete, Undo and persistence. Verification: targeted editing/persistence tests, analysis and real app smoke.

- [x] MVP-0311 Create and re-edit multiline text with keyboard/IME drafts.
  - Status: VERIFIED; priority: P0; dependencies: MVP-03A.
  - Acceptance: Create and re-edit multiline text with IME draft composition, modal text editor dialog, font size, wrap width, and color picker; tests: `test/editor_text_test.dart`; evidence: passing on host and Chrome web.

- [x] MVP-0312 Text size, color, direction, wrapping and resizing.
  - Status: VERIFIED; priority: P0; dependencies: MVP-03A.
  - Acceptance: Text typography fallback with Roboto and Noto Sans Arabic, auto/LTR/RTL direction detection, width wrapping, and bounding box selection/movement/resizing; tests: `test/editor_text_test.dart`; evidence: passing on host and Chrome web.

- [x] MVP-0313 Editable sticky notes with background colors and automatic height.
  - Status: VERIFIED; priority: P0; dependencies: MVP-03A.
  - Acceptance: Editable sticky notes with background fill colors, padding, automatic layout height, empty text deletion, and double-click re-editing; tests: `test/editor_text_test.dart`; evidence: passing on host and Chrome web.

- [x] MVP-0314 Verify Undo/Redo, cancellation, autosave/reopen and app smoke.
  - Status: VERIFIED; priority: P0; dependencies: MVP-03A.
  - Acceptance: Text and sticky note edits, moving, resizing, cancellation, and deletion survive undo/redo and autosave reopening; tests: `test/editor_text_test.dart`, `test/workspace_widget_test.dart`; evidence: passing on host and Chrome web.

## MVP-02 — Local Projects, Autosave & Reliable Reopening (verified)

Acceptance: preserve acknowledged completed edits across macOS app restart and Chrome reload, with an initial Board Library, ordered saves, accurate status and actionable failures. Undo/Redo remains session-only. No speculative rendering work. Dependencies: verified MVP-01 and production document contracts.

- [x] MVP-0201 Define strict versioned document/local snapshot serialization.
  - Status: VERIFIED; priority: P0; dependencies: MVP-01 and relevant MVP-02 serialization/store/coordinator contracts.
  - Acceptance: Round-trip every existing document value and reject malformed/unsupported snapshots without replacement. Tests: scoped automated and actual application checks; evidence: `benchmark_results/mvp-02/verification.json`,78 host/76 Chrome tests, real normal+isolated macOS restart, Chrome reload/tab reopening and forced native permission failure/retry/close protection.

- [x] MVP-0202 Implement durable native and IndexedDB stores.
  - Status: VERIFIED; priority: P0; dependencies: MVP-01 and relevant MVP-02 serialization/store/coordinator contracts.
  - Acceptance: Flush plus atomic native file replacement and browser transaction completion acknowledge writes; no in-memory fallback. Tests: scoped automated and actual application checks; evidence: `benchmark_results/mvp-02/verification.json`,78 host/76 Chrome tests, real normal+isolated macOS restart, Chrome reload/tab reopening and forced native permission failure/retry/close protection.

- [x] MVP-0203 Serialize revisioned autosave and retry.
  - Status: VERIFIED; priority: P0; dependencies: MVP-01 and relevant MVP-02 serialization/store/coordinator contracts.
  - Acceptance: One writer, generation compare-and-swap, newest pending snapshot, accurate acknowledged status and retained work on failure. Tests: scoped automated and actual application checks; evidence: `benchmark_results/mvp-02/verification.json`,78 host/76 Chrome tests, real normal+isolated macOS restart, Chrome reload/tab reopening and forced native permission failure/retry/close protection.

- [x] MVP-0204 Integrate Board Library and last-board restoration.
  - Status: VERIFIED; priority: P0; dependencies: MVP-01 and relevant MVP-02 serialization/store/coordinator contracts.
  - Acceptance: Create independent boards, reopen existing content, preserve viewport and restore last selected board. Tests: scoped automated and actual application checks; evidence: `benchmark_results/mvp-02/verification.json`,78 host/76 Chrome tests, real normal+isolated macOS restart, Chrome reload/tab reopening and forced native permission failure/retry/close protection.

- [x] MVP-0205 Protect pending saves and secondary sessions.
  - Status: VERIFIED; priority: P0; dependencies: MVP-01 and relevant MVP-02 serialization/store/coordinator contracts.
  - Acceptance: Flush before switch, retain current board on failure, close protection and read-only competing writers. Tests: scoped automated and actual application checks; evidence: `benchmark_results/mvp-02/verification.json`,78 host/76 Chrome tests, real normal+isolated macOS restart, Chrome reload/tab reopening and forced native permission failure/retry/close protection.

- [x] MVP-0206 Verify persistence regressions and actual macOS restart.
  - Status: VERIFIED; priority: P0; dependencies: MVP-01 and relevant MVP-02 serialization/store/coordinator contracts.
  - Acceptance: Run automated failure/order/round-trip tests plus real restart of isolated test instance. Tests: scoped automated and actual application checks; evidence: `benchmark_results/mvp-02/verification.json`,78 host/76 Chrome tests, real normal+isolated macOS restart, Chrome reload/tab reopening and forced native permission failure/retry/close protection.

- [x] MVP-0207 Verify actual Chrome reload and persistent backend.
  - Status: VERIFIED; priority: P0; dependencies: MVP-01 and relevant MVP-02 serialization/store/coordinator contracts.
  - Acceptance: Exercise IndexedDB across real reload/reopen and independent boards, distinguish simulated failures. Tests: scoped automated and actual application checks; evidence: `benchmark_results/mvp-02/verification.json`,78 host/76 Chrome tests, real normal+isolated macOS restart, Chrome reload/tab reopening and forced native permission failure/retry/close protection.

- [x] MVP-0208 Deliver manual checks, evidence and next milestone.
  - Status: VERIFIED; priority: P0; dependencies: MVP-01 and relevant MVP-02 serialization/store/coordinator contracts.
  - Acceptance: Update status/handoff with executed commands, limits, actual screenshots and next usable feature. Tests: scoped automated and actual application checks; evidence: `benchmark_results/mvp-02/verification.json`,78 host/76 Chrome tests, real normal+isolated macOS restart, Chrome reload/tab reopening and forced native permission failure/retry/close protection.

## MVP-01 — First Usable Whiteboard (verified)

Acceptance: normal entry point opens a real interactive editor on macOS and Chrome, using production document values. Usable canvas/pen/shapes, selection/movement/delete and bounded session Undo/Redo; functional toolbar. No benchmark-only completion claims. Following priority: local saving/reopening boards before advanced editing; then text/notes/images/frames, remaining tools, import/export/PNG, adaptive mobile, full platforms/performance hardening. All long-term tasks below retained.

Verification: meaningful command/geometry/widget regressions, clean analysis, actual normal-entry launches and real editor interaction/screenshots where supported.

- [x] MVP-0101 Connect normal entry point to real Editor screen.
  - Status: VERIFIED; priority: P0; dependencies: existing verified document/geometry contracts; integration with the other MVP-01 tasks.
  - Acceptance: Connect normal entry point to real Editor screen, under MVP-01 scope; tests: MVP-01 verification appropriate to behavior; evidence: `benchmark_results/mvp-01/verification.json`, focused host/Chrome tests and running-editor screenshots (scope/platform limitations retained).

- [x] MVP-0102 Implement world canvas, pan and anchor zoom.
  - Status: VERIFIED; priority: P0; dependencies: existing verified document/geometry contracts; integration with the other MVP-01 tasks.
  - Acceptance: Implement world canvas, pan and anchor zoom, under MVP-01 scope; tests: MVP-01 verification appropriate to behavior; evidence: `benchmark_results/mvp-01/verification.json`, focused host/Chrome tests and running-editor screenshots (scope/platform limitations retained).

- [x] MVP-0103 Implement mouse pen preview, commit and cancellation.
  - Status: VERIFIED; priority: P0; dependencies: existing verified document/geometry contracts; integration with the other MVP-01 tasks.
  - Acceptance: Implement mouse pen preview, commit and cancellation, under MVP-01 scope; tests: MVP-01 verification appropriate to behavior; evidence: `benchmark_results/mvp-01/verification.json`, focused host/Chrome tests and running-editor screenshots (scope/platform limitations retained).

- [x] MVP-0104 Implement basic rectangle, ellipse, triangle and line tools.
  - Status: VERIFIED; priority: P0; dependencies: existing verified document/geometry contracts; integration with the other MVP-01 tasks.
  - Acceptance: Implement basic rectangle, ellipse, triangle and line tools, under MVP-01 scope; tests: MVP-01 verification appropriate to behavior; evidence: `benchmark_results/mvp-01/verification.json`, focused host/Chrome tests and running-editor screenshots (scope/platform limitations retained).

- [x] MVP-0105 Integrate selection, precise hit testing and move previews.
  - Status: VERIFIED; priority: P0; dependencies: existing verified document/geometry contracts; integration with the other MVP-01 tasks.
  - Acceptance: Integrate selection, precise hit testing and move previews, under MVP-01 scope; tests: MVP-01 verification appropriate to behavior; evidence: `benchmark_results/mvp-01/verification.json`, focused host/Chrome tests and running-editor screenshots (scope/platform limitations retained).

- [x] MVP-0106 Implement delete and bounded session Undo/Redo with toolbar/keyboard.
  - Status: VERIFIED; priority: P0; dependencies: existing verified document/geometry contracts; integration with the other MVP-01 tasks.
  - Acceptance: Implement delete and bounded session Undo/Redo with toolbar/keyboard, under MVP-01 scope; tests: MVP-01 verification appropriate to behavior; evidence: `benchmark_results/mvp-01/verification.json`, focused host/Chrome tests and running-editor screenshots (scope/platform limitations retained).

- [x] MVP-0107 Verify editor correctness and actual macOS/Chrome launches.
  - Status: VERIFIED; priority: P0; dependencies: existing verified document/geometry contracts; integration with the other MVP-01 tasks.
  - Acceptance: Verify editor correctness and actual macOS/Chrome launches, under MVP-01 scope; tests: MVP-01 verification appropriate to behavior; evidence: `benchmark_results/mvp-01/verification.json`, focused host/Chrome tests and running-editor screenshots (scope/platform limitations retained).

- [x] MVP-0108 Deliver launch commands, screenshots, limitations and next persistence tasks.
  - Status: VERIFIED; priority: P0; dependencies: existing verified document/geometry contracts; integration with the other MVP-01 tasks.
  - Acceptance: Deliver launch commands, screenshots, limitations and next persistence tasks, under MVP-01 scope; tests: MVP-01 verification appropriate to behavior; evidence: `benchmark_results/mvp-01/verification.json`, focused host/Chrome tests and running-editor screenshots (scope/platform limitations retained).

## M00 — Repository Recovery & Planning

Acceptance contract: Existing code/evidence and staged changes reconciled; full durable backlog, reproducible verification and safe resume.

Verification contract: Repository inspection, task/link validation, analysis and host/Chrome regression.

- [x] WB-0001 Audit current repository and Git state.
  - Status: VERIFIED; priority: P0; dependencies: none.
  - Acceptance: **Audit current repository and Git state**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0002 Review all Phase 0–0.2 reports.
  - Status: VERIFIED; priority: P0; dependencies: none.
  - Acceptance: **Review all Phase 0–0.2 reports**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0003 Verify actual implemented features.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Verify actual implemented features**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0004 Reconcile existing benchmark evidence.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Reconcile existing benchmark evidence**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0005 Restore green analysis/tests if necessary.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Restore green analysis/tests if necessary**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: `benchmark_results/execution-01/baseline-verification.json`.

- [x] WB-0006 Create AGENTS.md.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Create AGENTS.md**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0007 Create MASTER_PLAN.md.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Create MASTER_PLAN.md**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0008 Create PROJECT_STATUS.md.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Create PROJECT_STATUS.md**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0009 Create ARCHITECTURE.md and DECISIONS.md.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Create ARCHITECTURE.md and DECISIONS.md**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0010 Create persistent HANDOFF.md.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Create persistent HANDOFF.md**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0011 Establish safe Git workflow and ignore generated artifacts.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Establish safe Git workflow and ignore generated artifacts**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

- [x] WB-0012 Define the baseline verification commands.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: **Define the baseline verification commands**, integrated where applicable under M00 contract; tests: M00 verification scoped to this deliverable; evidence: [execution recovery audit](DEVELOPMENT_LOG.md#2026-10-17--execution-recovery).

## M01 — Rendering Foundation Remediation

Acceptance contract: Full fidelity/order/alpha/RTL and bounded resources. Provisional interactive stage P95 ≤16.7 ms remains unchanged; cold readiness, physical input and presentation separately reported. No uncontrolled/short diagnostic qualifies the gate.

Verification contract: Host/Chrome geometry/cache/pixel regressions; matched profile normal/dense single/multi/stress/cold workloads with received samples, controls and memory/disposal.

- [x] WB-0101 Profile sustained-update benchmark methodology.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Profile sustained-update benchmark methodology**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: [Phase 0.3](phase-0.3-report.md), `benchmark_results/phase03/validation.json` (audited historical scope only).

- [ ] WB-0102 Separate mutation, paint, raster, and presentation costs.
  - Status: PLANNED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Separate mutation, paint, raster, and presentation costs**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

- [x] WB-0103 Identify remaining dominant bottlenecks.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Identify remaining dominant bottlenecks**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: [Phase 0.3](phase-0.3-report.md), `benchmark_results/phase03/validation.json` (audited historical scope only).

- [ ] WB-0104 Resolve unnecessary scene/cache invalidation.
  - Status: IN_PROGRESS; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Resolve unnecessary scene/cache invalidation**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

- [x] WB-0105 Investigate cold-cache stalls.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Investigate cold-cache stalls**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: [Phase 0.3](phase-0.3-report.md), `benchmark_results/phase03/validation.json` (audited historical scope only).

- [x] WB-0106 Fix or safely disable regressing cache strategies.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Fix or safely disable regressing cache strategies**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: [Phase 0.3](phase-0.3-report.md), `benchmark_results/phase03/validation.json` (audited historical scope only).

- [ ] WB-0107 Verify incremental element updates.
  - Status: PLANNED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Verify incremental element updates**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0108 Validate text/path caching correctness.
  - Status: PLANNED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Validate text/path caching correctness**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0109 Measure Chrome and macOS independently.
  - Status: PLANNED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Measure Chrome and macOS independently**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0110 Run memory stress tests.
  - Status: PLANNED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Run memory stress tests**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

- [x] WB-0111 Validate input measurement limitations.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Validate input measurement limitations**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: [Phase 0.3](phase-0.3-report.md), `benchmark_results/phase03/validation.json` (audited historical scope only).

- [ ] WB-0112 Establish realistic and stress workload budgets.
  - Status: PLANNED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Establish realistic and stress workload budgets**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0113 Document the accepted rendering strategy.
  - Status: PLANNED; priority: P0; dependencies: WB-0001, WB-0003, WB-0004, WB-0005.
  - Acceptance: **Document the accepted rendering strategy**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0114 Pass or explicitly resolve the rendering acceptance gate.
  - Status: PLANNED; priority: P0; dependencies: WB-0102, WB-0104, WB-0106, WB-0107, WB-0108, WB-0109, WB-0110, WB-0111, WB-0112, WB-0113.
  - Acceptance: **Pass or explicitly resolve the rendering acceptance gate**, integrated where applicable under M01 contract; tests: M01 verification scoped to this deliverable; evidence: pending.

## M02 — Document Model & Geometry

Acceptance contract: Pure Dart immutable versionable IDs/order/content/transforms; finite invertible geometry, acyclic ownership and explicit frame semantics; world-preserving reparent.

Verification contract: Nested transform/ID/order/cycle/orphan/±1e9/property tests; bounds/hits/index equivalence and malformed-value rejection.

- [x] WB-0201 Define versionable Document contracts.
  - Status: VERIFIED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Define versionable Document contracts**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: `benchmark_results/execution-03/verification.json`, `test/document_settings_test.dart` (9 new cases, full109 host/109 Chrome, clean analysis). Versioned immutable title/workspace/settings/resource/UTC metadata contracts; explicit unresolved legacy declarations. No codec/storage/editor integration; complete manifests must be required at those later boundaries.

- [x] WB-0202 Implement stable Element IDs.
  - Status: VERIFIED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement stable Element IDs**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: `benchmark_results/execution-02/verification.json`, `test/document_model_test.dart`, `test/document_geometry_test.dart` (90 host/90 Chrome; clean analysis; independent contracts only).

- [x] WB-0203 Implement all core Element Models.
  - Status: VERIFIED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement all core Element Models**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: `benchmark_results/execution-02/verification.json`, `test/document_model_test.dart`, `test/document_geometry_test.dart` (90 host/90 Chrome; clean analysis; independent contracts only).

- [x] WB-0204 Implement local/world coordinate transforms.
  - Status: VERIFIED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement local/world coordinate transforms**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: `benchmark_results/execution-02/verification.json`, `test/document_geometry_test.dart` (nine coordinate/property/overflow/deep-tree cases in 90 host/90 Chrome).

- [ ] WB-0205 Implement hierarchical Groups.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement hierarchical Groups**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0206 Implement Export Frame geometry.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement Export Frame geometry**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0207 Implement Container Frame ownership.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement Container Frame ownership**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0208 Implement safe reparenting.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement safe reparenting**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0209 Implement geometry validation.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement geometry validation**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

- [x] WB-0210 Prevent parent cycles and orphan references.
  - Status: VERIFIED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Prevent parent cycles and orphan references**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: `benchmark_results/execution-02/verification.json`, `test/document_model_test.dart`, `test/document_geometry_test.dart` (90 host/90 Chrome; clean analysis; independent contracts only).

- [ ] WB-0211 Implement accurate bounds and hit testing.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Implement accurate bounds and hit testing**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0212 Integrate with Spatial Index.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Integrate with Spatial Index**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0213 Verify large-world coordinate accuracy.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Verify large-world coordinate accuracy**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0214 Add geometry/invariant/property tests.
  - Status: PLANNED; priority: P0; dependencies: WB-0003 for independent contracts/tests; WB-0114 before renderer integration.
  - Acceptance: **Add geometry/invariant/property tests**, integrated where applicable under M02 contract; tests: M02 verification scoped to this deliverable; evidence: pending.

## M03 — Commands, Revisions & Undo/Redo

Acceptance contract: Atomic ordered revisions, reversible commands and rollback; session-only bounded/coalesced history; renderer receives incremental changes.

Verification contract: Execute/undo/redo round trips, failed transaction rollback, stale revision/coalescing/history limits and 10K mutation profile.

- [ ] WB-0301 Define Command execution contract.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Define Command execution contract**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0302 Implement atomic document mutations.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Implement atomic document mutations**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0303 Add/Delete/Update commands.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Add/Delete/Update commands**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0304 Move/Resize/Rotate commands.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Move/Resize/Rotate commands**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0305 Style/Text update commands.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Style/Text update commands**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0306 Group/Ungroup/Reparent commands.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Group/Ungroup/Reparent commands**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0307 Z-order and lock commands.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Z-order and lock commands**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0308 Implement session-only Undo/Redo.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Implement session-only Undo/Redo**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0309 Implement command coalescing.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Implement command coalescing**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0310 Bound Undo/Redo memory.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Bound Undo/Redo memory**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0311 Implement document revision ordering.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Implement document revision ordering**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0312 Integrate incremental rendering updates.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214, WB-0114, WB-0302, WB-0311.
  - Acceptance: **Integrate incremental rendering updates**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0313 Test command rollback and invariants.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Test command rollback and invariants**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0314 Benchmark document mutations.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, WB-0202, WB-0209, WB-0214.
  - Acceptance: **Benchmark document mutations**, integrated where applicable under M03 contract; tests: M03 verification scoped to this deliverable; evidence: pending.

## M04 — Input & Interaction Engine

Acceptance contract: Owned interaction state with deterministic commit/cancel/focus/tool/lifecycle; mouse/trackpad/keyboard/touch without duplicate/stale commands.

Verification contract: Pointer/keyboard/widget sequences, multi-touch/cancel/disposal/focus tests and actual device checks.

- [ ] WB-0401 Define interaction state machine.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Define interaction state machine**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0402 Implement pointer ownership.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Implement pointer ownership**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0403 Implement mouse input.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Implement mouse input**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0404 Implement touch input.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Implement touch input**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0405 Implement pan and zoom gestures.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Implement pan and zoom gestures**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0406 Handle multi-touch transitions.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Handle multi-touch transitions**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0407 Implement keyboard shortcuts.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Implement keyboard shortcuts**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0408 Handle focus and IME conflicts.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Handle focus and IME conflicts**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0409 Implement Commit/Cancel interaction lifecycle.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Implement Commit/Cancel interaction lifecycle**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0410 Handle tool switching safely.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Handle tool switching safely**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0411 Handle screen disposal and lifecycle changes.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Handle screen disposal and lifecycle changes**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0412 Prevent duplicate/stale commands.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Prevent duplicate/stale commands**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0413 Add deterministic interaction tests.
  - Status: PLANNED; priority: P1; dependencies: WB-0301, WB-0302, WB-0312.
  - Acceptance: **Add deterministic interaction tests**, integrated where applicable under M04 contract; tests: M04 verification scoped to this deliverable; evidence: pending.

## M05 — Drawing Tools

Acceptance contract: Requested tools emit correct commands; previews avoid per-pointer document copies; highlighter alpha and erased stroke geometry preserved.

Verification contract: Stroke/splitting/eraser/shape invariants, widget commit/cancel/undo tests and active drawing profile.

- [ ] WB-0501 Implement Pen.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Pen**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0502 Implement stroke smoothing/sampling.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement stroke smoothing/sampling**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0503 Implement Highlighter.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Highlighter**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0504 Validate alpha blending.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Validate alpha blending**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0505 Implement Object Eraser.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Object Eraser**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0506 Implement Segment Eraser.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Segment Eraser**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0507 Implement stroke splitting geometry.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement stroke splitting geometry**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0508 Implement Rectangle.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Rectangle**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0509 Implement Ellipse.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Ellipse**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0510 Implement Triangle.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Triangle**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0511 Implement Line.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Line**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0512 Implement Free Arrow.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Implement Free Arrow**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0513 Add configurable colors/widths/styles.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Add configurable colors/widths/styles**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0514 Integrate all tools with Commands.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Integrate all tools with Commands**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0515 Add drawing/eraser geometry tests.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Add drawing/eraser geometry tests**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0516 Benchmark active drawing performance.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0409, WB-0303.
  - Acceptance: **Benchmark active drawing performance**, integrated where applicable under M05 contract; tests: M05 verification scoped to this deliverable; evidence: pending.

## M06 — Selection & Transform Editing

Acceptance contract: Selection/handles/transforms honor overlap order, locks and nested transforms; completed interaction yields one command.

Verification contract: Overlap/rotation/marquee/group/lock tests, cancel/undo round trips and mouse/touch checks.

- [ ] WB-0601 Single selection.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Single selection**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0602 Multi-selection.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Multi-selection**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0603 Marquee selection.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Marquee selection**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0604 Selection overlay.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Selection overlay**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0605 Hit testing for overlaps/rotation.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Hit testing for overlaps/rotation**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0606 Move selected elements.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Move selected elements**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0607 Resize selected elements.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Resize selected elements**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0608 Rotate selected elements.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Rotate selected elements**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0609 Preserve group-relative transforms.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Preserve group-relative transforms**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0610 Add screen-space selection handles.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Add screen-space selection handles**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0611 Respect locked elements.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Respect locked elements**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0612 Integrate Undo/Redo.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Integrate Undo/Redo**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0613 Add transform interaction tests.
  - Status: PLANNED; priority: P1; dependencies: WB-0409, WB-0304, WB-0211.
  - Acceptance: **Add transform interaction tests**, integrated where applicable under M06 contract; tests: M06 verification scoped to this deliverable; evidence: pending.

## M07 — Text, Sticky Notes, Images & Frames

Acceptance contract: Native editable multiline Arabic/English/mixed text and IME; bounded stale-safe images; correct frame ownership and legally redistributable fonts.

Verification contract: RTL/IME/editing widget tests, decode/error/disposal tests, frame invariants, font-license audit and device checks.

- [x] WB-0701 Implement text rendering.
  - Status: VERIFIED; priority: P1; dependencies: WB-0305, WB-0601.
  - Acceptance: **Implement text rendering**, integrated where applicable under M07/MVP-03B contract with font fallback and text layout; tests: `test/editor_text_test.dart`; evidence: verified on host and Chrome.

- [x] WB-0702 Implement editable text overlay.
  - Status: VERIFIED; priority: P1; dependencies: WB-0305, WB-0601.
  - Acceptance: **Implement editable text overlay**, integrated where applicable under M07/MVP-03B contract with modal draft editor and double-click re-editing; tests: `test/editor_text_test.dart`; evidence: verified on host and Chrome.

- [x] WB-0703 Arabic/RTL and mixed-direction text.
  - Status: VERIFIED; priority: P1; dependencies: WB-0305, WB-0601.
  - Acceptance: **Arabic/RTL and mixed-direction text**, integrated where applicable under M07/MVP-03B contract with automatic direction detection and bundled font fallback; tests: `test/editor_text_test.dart`; evidence: verified on host and Chrome.

- [x] WB-0704 Cursor, selection, and IME.
  - Status: VERIFIED; priority: P1; dependencies: WB-0305, WB-0601.
  - Acceptance: **Cursor, selection, and IME**, integrated where applicable under M07/MVP-03B contract with IME composing text input and selection bounding box; tests: `test/editor_text_test.dart`; evidence: verified on host and Chrome.

- [x] WB-0705 Auto-resize and wrapping.
  - Status: VERIFIED; priority: P1; dependencies: WB-0305, WB-0601.
  - Acceptance: **Auto-resize and wrapping**, integrated where applicable under M07/MVP-03B contract with maxWidth layout and adjustable wrap width; tests: `test/editor_text_test.dart`; evidence: verified on host and Chrome.

- [x] WB-0706 Implement Sticky Notes.
  - Status: VERIFIED; priority: P1; dependencies: WB-0305, WB-0601.
  - Acceptance: **Implement Sticky Notes**, integrated where applicable under M07/MVP-03B contract with background fill colors, padding, and empty deletion; tests: `test/editor_text_test.dart`; evidence: verified on host and Chrome.

- [x] WB-0707 Sticky Note styles and resize.
  - Status: VERIFIED; priority: P1; dependencies: WB-0305, WB-0601.
  - Acceptance: **Sticky Note styles and resize**, integrated where applicable under M07/MVP-03B contract with background color presets and auto-height text layout; tests: `test/editor_text_test.dart`; evidence: verified on host and Chrome.

- [ ] WB-0708 Implement image import and display.
  - Status: PLANNED; priority: P1; dependencies: WB-0305, WB-0601; image/frame tasks also WB-0203, WB-0207.
  - Acceptance: **Implement image import and display**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0709 Implement lazy/resolution-aware image decode.
  - Status: PLANNED; priority: P1; dependencies: WB-0305, WB-0601; image/frame tasks also WB-0203, WB-0207.
  - Acceptance: **Implement lazy/resolution-aware image decode**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0710 Implement bounded image caching.
  - Status: PLANNED; priority: P1; dependencies: WB-0305, WB-0601; image/frame tasks also WB-0203, WB-0207.
  - Acceptance: **Implement bounded image caching**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0711 Handle stale async image loading.
  - Status: PLANNED; priority: P1; dependencies: WB-0305, WB-0601; image/frame tasks also WB-0203, WB-0207.
  - Acceptance: **Handle stale async image loading**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0712 Implement Export Frame editing.
  - Status: PLANNED; priority: P1; dependencies: WB-0305, WB-0601; image/frame tasks also WB-0203, WB-0207.
  - Acceptance: **Implement Export Frame editing**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0713 Implement Container Frame editing.
  - Status: PLANNED; priority: P1; dependencies: WB-0305, WB-0601; image/frame tasks also WB-0203, WB-0207.
  - Acceptance: **Implement Container Frame editing**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0714 Preserve frame/group hierarchy invariants.
  - Status: PLANNED; priority: P1; dependencies: WB-0305, WB-0601; image/frame tasks also WB-0203, WB-0207.
  - Acceptance: **Preserve frame/group hierarchy invariants**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0715 Verify fonts and licensing.
  - Status: IN_PROGRESS; priority: P1; dependencies: WB-0003; font/license research is independent of commands and selection.
  - Acceptance: **Verify fonts and licensing**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: benchmark-only fonts/licensing verified under WB-0120, production curation/editor/portable/export/platform fidelity still pending.

- [ ] WB-0716 Add relevant cross-platform tests.
  - Status: PLANNED; priority: P1; dependencies: WB-0305, WB-0601; image/frame tasks also WB-0203, WB-0207.
  - Acceptance: **Add relevant cross-platform tests**, integrated where applicable under M07 contract; tests: M07 verification scoped to this deliverable; evidence: pending.

## M08 — Advanced Editing

Acceptance contract: Advanced operations preserve nested transforms/order/locks/assets and atomic undo; desktop/mobile actions integrate with editor.

Verification contract: Nested operation+undo, clipboard asset validation, deterministic snapping/alignment and dense profile.

- [ ] WB-0801 Group/Ungroup UI.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Group/Ungroup UI**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0802 Enter/Exit Group editing.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Enter/Exit Group editing**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0803 Alignment.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Alignment**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0804 Distribution.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Distribution**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0805 Grid snapping.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Grid snapping**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0806 Object snapping.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Object snapping**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0807 Alignment guides.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Alignment guides**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0808 Z-order controls.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Z-order controls**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0809 Lock/Unlock.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Lock/Unlock**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0810 Duplicate.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Duplicate**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0811 Internal Copy/Cut/Paste.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Internal Copy/Cut/Paste**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0812 Safe clipboard asset references.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Safe clipboard asset references**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0813 Desktop context menus.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Desktop context menus**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0814 Mobile contextual actions.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Mobile contextual actions**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0815 Verify nested editing and Undo/Redo.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Verify nested editing and Undo/Redo**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0816 Benchmark dense advanced editing.
  - Status: PLANNED; priority: P1; dependencies: WB-0306, WB-0307, WB-0612.
  - Acceptance: **Benchmark dense advanced editing**, integrated where applicable under M08 contract; tests: M08 verification scoped to this deliverable; evidence: pending.

## M09 — Local Persistence & Asset Storage

Execution priority: immediately after MVP-01, before advanced editing. Implement save/reopen for currently supported editor content, then expand with future content; never silently drop unsupported data. MVP-0106 supplies the current tested revision/commit boundary; full generic M03 expansion is not a prerequisite for starting storage.

Acceptance contract: Workspace durably confirms latest ordered revisions/assets; serialized saves, honest status, single writer/read-only secondary and recoverable failures.

Verification contract: Stale-save/retry/quota/disk/permission/crash/reload fault tests, asset/library consistency and browser writer coordination.

- [ ] WB-0901 Evaluate maintained storage technologies.
  - Status: PLANNED; priority: P0; dependencies: WB-0003; storage research may proceed before document integration.
  - Acceptance: **Evaluate maintained storage technologies**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0902 Select and document database architecture.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Select and document database architecture**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0903 Implement Workspace schema.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement Workspace schema**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0904 Implement document persistence.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement document persistence**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0905 Implement serialized save queue.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement serialized save queue**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0906 Implement revision ordering.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement revision ordering**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0907 Implement honest save status.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement honest save status**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0908 Implement original asset storage.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement original asset storage**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0909 Implement asset staging/commit.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement asset staging/commit**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0910 Implement safe asset garbage collection.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement safe asset garbage collection**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [x] WB-0911 Implement Board Library operations.
  - Status: VERIFIED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement Board Library operations** including rename, duplicate, and delete with confirmation dialog; atomic deletion in FileBoardStore and WebBoardStore; lifecycle-bound TextEditingController dialog to prevent post-dismissal disposal exceptions; auto-syncing board session and title without version conflicts; tests: `test/file_board_store_test.dart`, `test/web_board_store_test.dart`, `test/workspace_widget_test.dart`; evidence: 214 host tests and 83 Chrome tests passing with 0 analyzer issues.

- [ ] WB-0912 Implement schema migrations.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement schema migrations**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0913 Implement Web persistent storage validation.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement Web persistent storage validation**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0914 Implement single-writer/read-only coordination.
  - Current MVP-02 evidence: native process/browser-tab exclusion verified. Broader qualification remains unchecked, including debug Flutter R hot-restart cleanup; full page reload releases the stale page lock. Do not steal live locks.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement single-writer/read-only coordination**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0915 Implement crash recovery.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Implement crash recovery**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0916 Handle quota, disk-full, permission failures.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Handle quota, disk-full, permission failures**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0917 Test stale save/retry races.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Test stale save/retry races**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

- [ ] WB-0918 Run actual reload/recovery verification.
  - Status: PLANNED; priority: P0; dependencies: WB-0201, MVP-0106 (current editor); full command expansion tracked under WB-0311.
  - Acceptance: **Run actual reload/recovery verification**, integrated where applicable under M09 contract; tests: M09 verification scoped to this deliverable; evidence: pending.

## M10 — Portable Project Files

Acceptance contract: Independent versioned snapshots/imports include validated checksums/assets/legal fonts; reject corrupt, oversized, traversal/bomb/unsupported input without silent loss.

Verification contract: Cross-platform round trip, malformed/fuzz/size/path/checksum/schema cases, interrupted import and Save As independence.

- [ ] WB-1001 Define `.wboard` versioned format.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Define `.wboard` versioned format**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1002 Implement Manifest.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Implement Manifest**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1003 Implement document serialization.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Implement document serialization**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1004 Include original assets.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Include original assets**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1005 Implement font references/assets legally.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Implement font references/assets legally**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1006 Implement Checksums.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Implement Checksums**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1007 Implement safe archive validation.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Implement safe archive validation**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1008 Protect against malformed/oversized archives.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Protect against malformed/oversized archives**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1009 Implement independent Project Import.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Implement independent Project Import**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1010 Implement Save As independent snapshot.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Implement Save As independent snapshot**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1011 Implement format migrations.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Implement format migrations**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1012 Test cross-platform round-trip.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Test cross-platform round-trip**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1013 Test interrupted imports and corrupt projects.
  - Status: PLANNED; priority: P1; dependencies: WB-0904, WB-0908, WB-0912.
  - Acceptance: **Test interrupted imports and corrupt projects**, integrated where applicable under M10 contract; tests: M10 verification scoped to this deliverable; evidence: pending.

## M11 — PNG Export

Acceptance contract: Independent offscreen PNG respects bounds/frame clipping/background/resolution and memory limits; actionable failure/cancel.

Verification contract: Dimensions/alpha/clipping/text/image pixels, 4K/custom limits and device export peak memory/time.

- [ ] WB-1101 Define export bounds model.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Define export bounds model**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1102 Implement independent offscreen rendering.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Implement independent offscreen rendering**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1103 Viewport export.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Viewport export**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1104 Selection export.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Selection export**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1105 Frame export with clipping.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Frame export with clipping**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1106 Custom area export.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Custom area export**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1107 Transparent and solid backgrounds.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Transparent and solid backgrounds**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1108 Resolution presets including 4K.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Resolution presets including 4K**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1109 Custom width/height.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Custom width/height**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1110 Image/Font rendering fidelity.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Image/Font rendering fidelity**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1111 Implement memory-aware export limits.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Implement memory-aware export limits**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1112 Investigate tiling/streaming if necessary.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Investigate tiling/streaming if necessary**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1113 Implement cancellation/error recovery.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Implement cancellation/error recovery**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1114 Test dimensions, clipping, transparency.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Test dimensions, clipping, transparency**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1115 Benchmark export memory/time on supported devices.
  - Status: PLANNED; priority: P1; dependencies: WB-0211, WB-0712, WB-0715; offscreen contract before integration.
  - Acceptance: **Benchmark export memory/time on supported devices**, integrated where applicable under M11 contract; tests: M11 verification scoped to this deliverable; evidence: pending.

## M12 — Product UI & UX

Acceptance contract: Coherent accessible adaptive full-function editor/library, compact phone controls, honest operation feedback and predictable shortcuts.

Verification contract: Widget/semantics/responsive/visual tests, keyboard navigation and real desktop/mobile usability.

- [x] WB-1201 Establish coherent design system.
  - Status: VERIFIED; priority: P1; dependencies: WB-0003; independent design may proceed before editor implementation.
  - Acceptance: **Establish coherent design system**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1202 Design Board Library.
  - Status: VERIFIED; priority: P1; dependencies: WB-0003, WB-1201; design precedes WB-0911 implementation.
  - Acceptance: **Design Board Library**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1203 Design Editor layout.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Design Editor layout**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1204 Implement desktop toolbar.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement desktop toolbar**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1205 Implement contextual properties controls.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement contextual properties controls**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1206 Implement mobile adaptive toolbar.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement mobile adaptive toolbar**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1207 Implement touch-friendly editing controls.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement touch-friendly editing controls**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1208 Implement zoom/navigation UI.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement zoom/navigation UI**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1209 Implement color/stroke pickers.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement color/stroke pickers**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1210 Implement board creation/opening flow.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement board creation/opening flow**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1211 Implement Save/Error/Recovery feedback.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement Save/Error/Recovery feedback**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [ ] WB-1212 Implement Import/Export UX.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement Import/Export UX**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: pending.

- [x] WB-1213 Implement keyboard shortcuts/help.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Implement keyboard shortcuts/help**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [ ] WB-1214 Accessibility and semantics review.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Accessibility and semantics review**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: pending.

- [x] WB-1215 Empty/loading/error states.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Empty/loading/error states**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [x] WB-1216 Responsive and visual consistency testing.
  - Status: VERIFIED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Responsive and visual consistency testing**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

- [ ] WB-1217 Real-device usability refinement.
  - Status: PLANNED; priority: P1; dependencies: WB-0401, WB-0604, WB-0702; library WB-0911, feedback WB-0907.
  - Acceptance: **Real-device usability refinement**, integrated where applicable under M12 contract; tests: M12 verification scoped to this deliverable; evidence: pending.

## M13 — Platform Compatibility

Acceptance contract: Actual OS/device/backend builds and runtime outcomes recorded; unavailable coverage stays pending, never inferred from tool presence.

Verification contract: Windows/macOS/Chrome/Edge/Safari/Android/iOS runs plus real input/IME/files/storage/lifecycle/performance matrix.

- [ ] WB-1301 Windows desktop validation.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Windows desktop validation**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1302 macOS desktop validation.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **macOS desktop validation**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1303 Chrome Web validation.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Chrome Web validation**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1304 Edge Web validation.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Edge Web validation**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1305 Safari Web validation.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Safari Web validation**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1306 Android validation.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Android validation**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1307 iOS validation.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **iOS validation**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1308 Mouse/trackpad interaction checks.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Mouse/trackpad interaction checks**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1309 Touch gesture checks.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Touch gesture checks**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1310 Keyboard/IME/RTL checks.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Keyboard/IME/RTL checks**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1311 File Picker/Save behavior.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **File Picker/Save behavior**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1312 App lifecycle and background/resume.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **App lifecycle and background/resume**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1313 Storage compatibility.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Storage compatibility**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1314 Platform-specific performance checks.
  - Status: PLANNED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Platform-specific performance checks**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: pending.

- [x] WB-1315 Record unsupported/unavailable hardware tests.
  - Status: VERIFIED; priority: P1; dependencies: relevant implemented feature; environment discovery after WB-0001.
  - Acceptance: **Record unsupported/unavailable hardware tests**, integrated where applicable under M13 contract; tests: M13 verification scoped to this deliverable; evidence: `benchmark_results/ui-ux/verification.json`; macOS/Chrome UI and focused tests, native mobile qualification remains separate.

## M14 — Production Hardening

Acceptance contract: Integrated correctness/reliability/security/lifecycle/memory/performance/accessibility gates pass; no placeholder release behavior.

Verification contract: Full unit/widget/integration/property/fault/fuzz/stress suites, dependency/security review and device acceptance.

- [ ] WB-1401 Full static analysis.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Full static analysis**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1402 Unit test coverage review.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Unit test coverage review**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1403 Widget tests.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Widget tests**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1404 Integration tests.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Integration tests**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1405 Geometry/property tests.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Geometry/property tests**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1406 Undo/Redo stress tests.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Undo/Redo stress tests**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1407 Storage failure injection.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Storage failure injection**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1408 Crash recovery tests.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Crash recovery tests**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1409 Portable file fuzz/validation tests.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Portable file fuzz/validation tests**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1410 Large document stress tests.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Large document stress tests**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1411 Performance regression benchmarks.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Performance regression benchmarks**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1412 Memory leak and lifecycle tests.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Memory leak and lifecycle tests**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1413 Security review.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Security review**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1414 Package/dependency audit.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Package/dependency audit**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1415 Accessibility review.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Accessibility review**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1416 Remove debug-only behavior from release.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Remove debug-only behavior from release**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1417 Release configuration review.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **Release configuration review**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1418 End-to-end acceptance testing.
  - Status: PLANNED; priority: P1; dependencies: relevant M02–M13 implementation/test tasks.
  - Acceptance: **End-to-end acceptance testing**, integrated where applicable under M14 contract; tests: M14 verification scoped to this deliverable; evidence: pending.

## M15 — CI, Packaging & Production Release

Acceptance contract: Reproducible CI/artifacts/metadata/docs; mandatory platform qualification evidenced; signing/publication require identity and explicit authorization.

Verification contract: CI matrix, installation/recovery/offline and authorized signed-artifact checks, release-candidate acceptance/evidence review.

- [ ] WB-1501 Set up reliable CI validation.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Set up reliable CI validation**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1502 Configure test/build matrix.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Configure test/build matrix**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1503 Configure production app metadata.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Configure production app metadata**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1504 Configure app icons/assets.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Configure app icons/assets**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1505 Prepare Windows distribution.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Prepare Windows distribution**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1506 Prepare macOS distribution.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Prepare macOS distribution**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1507 Prepare Web production build.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Prepare Web production build**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1508 Prepare Android release build.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Prepare Android release build**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1509 Prepare iOS release build.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Prepare iOS release build**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1510 Document signing/notarization requirements.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Document signing/notarization requirements**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1511 Document browser deployment requirements.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Document browser deployment requirements**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1512 Create release notes and changelog.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Create release notes and changelog**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1513 Create user-facing backup limitations.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Create user-facing backup limitations**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1514 Prepare installation and recovery documentation.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Prepare installation and recovery documentation**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1515 Conduct release candidate verification.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Conduct release candidate verification**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1516 Complete final security/performance review.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Complete final security/performance review**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1517 Produce release artifacts where toolchains allow.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Produce release artifacts where toolchains allow**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1518 Identify external publishing/account requirements.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Identify external publishing/account requirements**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

- [ ] WB-1519 Final production readiness sign-off.
  - Status: PLANNED; priority: P2; dependencies: WB-1418 for release; CI may start after WB-0012.
  - Acceptance: **Final production readiness sign-off**, integrated where applicable under M15 contract; tests: M15 verification scoped to this deliverable; evidence: pending.

## M01 remediation subtasks — bounded dirty-region experiment

- [x] WB-0115 Implement opt-in dirty-region tile repair.
  - Status: VERIFIED; priority: P0; dependencies: WB-0101, WB-0103, WB-0105, WB-0118.
  - Acceptance: preserve clean pixels, replace damage using conservative old/new bounds and original order, suppress stale async publication, bound resources and fragmentation; reference/default unchanged. Tests: alpha/order/gutter/fractional/large-world pixels, repeated/multi-tile/in-flight edits, errors and disposal. Evidence: `benchmark_results/execution-01/verification.json` (61 host/61 Chrome, clean analysis, independent review).
- [x] WB-0116 Collect matched bounded dirty-repair profile evidence.
  - Status: VERIFIED; priority: P0; dependencies: WB-0115.
  - Acceptance: identical profile workloads/viewport reference/candidate, all received stages/counts/controls and dirty replay/cache stats for normal/dense single/multi first. If the candidate remains over budget or regresses multi, reject promotion before a full cold/navigation/soak sweep and explicitly retain those validations as pending; no rendering target is waived. Tests: profile builds and strict bounded collector validation. Evidence: `benchmark_results/execution-01/web-dirty-repair-summary.json`, `macos-dirty-repair-summary.json` (three clean rows each, not qualification).
- [x] WB-0117 Review, integrate or reject the experiment and select remediation.
  - Status: VERIFIED; priority: P0; dependencies: WB-0116.
  - Acceptance: independent correctness review and measured trade-offs/stopping rule recorded; no target relaxation or cache promotion. Tests: 61 host/61 Chrome regressions, clean analysis, strict paired diagnostics. Evidence: ADR-003–005, `benchmark_results/execution-01/verification.json`; reject promotion, retain default-off experiment and move to ordered retention feasibility.

## Recovery subtasks discovered during execution

- [x] WB-0013 Restore compiler disk capacity and rerun affected verification.
  - Status: VERIFIED; priority: P0; dependencies: WB-0001.
  - Acceptance: several GiB free and compiler runs complete; remove only identified ignored project outputs, preserve user data/index/source/evidence. Tests: disk check, focused host/Chrome compiler retry; evidence: `benchmark_results/execution-01/environment-recovery.json`, `verification.json` (capacity recovered; focused/full compilers complete; failed attempts retained).
- [x] WB-0118 Resolve Chrome dirty-region stale pixels without loosening assertions.
  - Status: VERIFIED; priority: P0; dependencies: WB-0103, WB-0013.
  - Acceptance: iterative rectangle exclusion must erase old red pixels and avoid double-blended blue; original exact alpha/order assertions plus all eight repair tests pass host/Chrome. Tests: `test/dirty_tile_repair_test.dart`, then full regression; evidence: `benchmark_results/execution-01/verification.json` (rectangular exclusion fixed actual stale alpha; all 61 host and 61 Chrome tests passed).

- [ ] WB-0119 Prototype bounded ordered retained ranges with transient editing.
  - Status: IN_PROGRESS; priority: P0; dependencies: WB-0117.
  - Acceptance: preserve source order/alpha/large-world/culling and the existing scene/index; no manual whole-tile regeneration per preview/commit without evidence. Compare retained vector ranges/on-screen layer reuse against current direct/tile paths; bound range fragmentation/resources and fall back safely. First-use/cold cost must be recorded, never hidden. Tests: ordered overlap/move/cancel/commit/pixel/race/disposal tests then matched profile local/multi/navigation/cold; retain default-off until full gate. Evidence: ADR-005–011, execution-02/03 and retained pixel suites (109 host/109 Chrome). Actual bounded on-screen layers now implemented; Chrome four-row and native dense-only matched Profile diagnostics remain insufficient for cross-platform acceptance. Chrome dense25.6/25.2ms; interleaving triggers bounded direct fallback. Native prefix3.965/5.057ms promising, normal baseline lifecycle-contaminated. No promotion; navigation/cold/tile comparison/full qualification remain pending. Execution04 observed CanvasKit/single/multi Wasm profiles all over budget; reject backend promotion (ADR-012). Wasm test harness failed before cases. Startup audit found external font fallback pending at READY. Execution05 WB-0120 now verified fixed fonts/readiness and genuine-font tests; dense direct33.221/33.935/33.335ms, vectors27.485/26.850/25.230ms, layers25.675/26.495/33.959ms. Still NO-GO. Fractional tile text uses reported full direct fallback, matching-scale subpixel fidelity unqualified. Next prove exact camera/device-phase pixels and bounded first-use/resource behavior before ADR-012 selection-scoped raster experiment; no cache promotion or budget/platform waiver.

- [x] WB-0120 Control benchmark font assets and readiness.
  - Status: VERIFIED; priority: P0; dependencies: WB-0003; discovered during WB-0119; independent WB-0715 license research permitted.
  - Acceptance: fixed licensed font bytes and corpus coverage, explicit awaited/error readiness and engine ownership, genuine-font host/Chrome tests, matched profile controls with no external font requests; preserve historical sources/metrics and rendering target. Tests: asset/license/cmap audit, loading/retry/late/disposal and retained pixels, full host/Chrome regression and local-only browser startup. Evidence: execution-05/verification.json, font-assets.json, font-profile-validation.json;116 host/116 Chrome and clean analysis,12 matched Profile rows/2,911 frames/617 commits,18 malformed profile cases rejected plus4 malformed asset cases. Four fonts complete locally before READY; external-blocked startup548.517ms. Original warm glyph mismatch preserved and contained by reported direct fallback, never claimed as repaired-raster fidelity. Rendering remains NO-GO; mandatory platform/phase/shaping guarantees unchanged.

## M14 deferred stress-performance obligation

The unresolved WB-0114 gate, WB-0119 speculative caching and related cold/navigation/all-visible/long-memory/input/platform requirements remain retained and unverified. They are scheduled during Production Hardening under the user priority override, not prerequisites for this usable slice.10,000-element performance and16.7ms provisional target are preserved. Do not repeat benchmark experiments before the usable product and earlier-priority persistence/features.
