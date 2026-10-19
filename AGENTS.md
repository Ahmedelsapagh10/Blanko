# Whiteboard engineering instructions

Build the existing single-user, local-first Flutter Whiteboard into verified V1 for Windows, macOS, Chrome/Edge/Safari, Android and iOS. Product requirements and authorization: [execution directive](docs/EXECUTION_DIRECTIVE.md). This directive supersedes historical report approval stops; failed technical gates trigger remediation, never an invented pass.

Current priority override2026-10-19: MVP-01 usable editor and MVP-02 local persistence/reopening are verified; next implement the usable text/notes slice. Dense performance remains an unverified Production Hardening obligation; speculative caching/fonts/benchmarks paused and do not gate unrelated editor integration. Follow the latest explicit user priority in the directive/master plan.

## Resume and track

- On `continue`, read this file, `docs/HANDOFF.md`, `docs/PROJECT_STATUS.md`, `docs/MASTER_PLAN.md`, then inspect Git changes and relevant code/tests. Perform actual engineering work.
- MASTER_PLAN is the canonical backlog. Each task has dependencies, priority, acceptance, tests and evidence. Check only verified work; keep IN_PROGRESS/BLOCKED tasks unchecked.
- Coordinator owns canonical documents/integration. Use supported agents for independent scopes with explicit file ownership, deliverables and validation; never overlap shared contracts or Git writes.
- Update status, decisions, risks, tests, performance and handoff when evidence changes. Progress is checked tasks / all tracked tasks, not a subjective estimate.

## Implementation

- Inspect and reuse existing architecture, names and conventions. Minimal maintainable changes; preserve unrelated functionality and the user's staged/unstaged work.
- Reuse pure Dart geometry, camera and spatial index. BenchmarkScene is a synthetic transform-only fixture, not the production document schema. Keep UI/resources out of document state.
- No new dependency, architecture, state management or SDK/package upgrade without demonstrated need. Verify official compatibility before adopting packages. No backend/auth/cloud/collaboration.
- Keep pointer previews separate from committed immutable changes. Preserve z-order, alpha, RTL, hierarchy and world-space transforms. No full-scene copies per pointer event or unbounded caches.
- Explicitly own/dispose images, pictures, controllers and subscriptions. Suppress stale async publication and propagate actionable errors. Never invent API contracts/secrets.
- After two ineffective remediation strategies, reassess alternatives and record trade-offs before another experiment. Do not optimize indefinitely or silently weaken guarantees.

## Quality and completion

- Run focused meaningful tests, relevant regressions and static analysis. Baseline commands/platform limits: `docs/TEST_MATRIX.md`.
- Performance claims require executed profile/release runs, full distributions, environment and reproducible evidence; distinguish engine stages from presentation/input-to-photon. Preserve historical evidence.
- Done means implemented, integrated where applicable, regression/analysis green, invariants/lifecycle/errors/performance reviewed, and evidence recorded. Missing device verification stays a separate unchecked task.
- Preserve Git index; no blanket add/reset/force-push. Generated caches/builds stay ignored; retain small summaries rather than unnecessary large traces.
- User input is needed for material scope/guarantee changes, destructive user-data actions, paid services, unavailable credentials/accounts, signing/public publishing, or genuinely exhausted decisions. Ordinary local fixes/refactors/tests/remediation are authorized.
- End sessions with the directive's concise progress format and exact next actions in HANDOFF. Never claim background execution or production readiness without mandatory platform evidence.
