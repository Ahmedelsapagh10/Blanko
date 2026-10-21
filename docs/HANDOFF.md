# Blanko handoff

PNG fix2026-10-21: centered uniform Fit replaces independent X/Y stretch. Padding uses selected background; source rectangle/exact Export Frame polygon clips exclude outside art. Frame view removes only rotation/translation, preserving scaled/sheared world geometry. Dialog defaults reflect visual Frame bounds and explains Fit. Full original-image decode retained; no schema/dependency or artwork changes.19 host/17 Chrome tests pass(2 native-only skips), analysis clean; actual native4K and Chrome4K/custom-square/viewport files verified. Evidence + before reproduction/after app outputs: `benchmark_results/png-fit/verification.json`. Controlled PNG aspect proof Boards added independently on macOS/Chrome; other user Boards untouched.137/275 unchanged. STOP for review after commit/push; no unrelated milestone.


2026-10-21. **137/275 checked.** Assigned Advanced Editing integrated; stop for review. Git commit/push details are in the delivery/Git log. No packages, SDK or storage schema changed; existing Boards and original assets retained.

## Use

`flutter run -d macos`

`flutter run -d web-server --web-port=8772 --web-hostname=localhost`

Select(V): Shift-click toggles; drag empty canvas for intersecting marquee; Esc restores pre-marquee selection or clears selection; Ctrl/Cmd+A selects eligible roots. Shared corners uniformly resize artwork/groups; rotation handle and toolbar rotate use shared pivot. Single Frame corners change rectangle only. Group via Ctrl/Cmd+G; Shift+Ctrl/Cmd+G ungroups. Select→Selection actions/right-click exposes Copy/Cut/Paste, Group entry/exit, ordering, six alignments/two distributions, lock discovery, snapping and touch multi-select. Long-press in Select opens context actions; phone layout uses bottom sheet. Text dialogs retain native editing shortcuts.

Semantics: Groups act as units until Edit group contents. Marquee intersects visual AABBs; Frames require full enclosure so a marquee inside a Frame can select children. Selected ancestors normalize away descendants. Grouping only same-parent siblings, at the frontmost selected sibling's layer; selected relative order/world appearance survives. Alignment/distribution require same parent and preserve sizes. Paste retains source-world layout near viewport or with visible offset. Clipboard belongs to Workspace, survives Board switching and source deletion, ends on app restart. Originals staged under fresh IDs before one insert revision; stale/disposed destination cannot publish. No OS clipboard promise. Locks inherit; any locked descendant protects its owner from bulk transforms/deletion. Locked items menu finds offscreen locks; unlock ancestors first. Clear All refuses locked content. Guides/handles/lock badges are editor-only and never export.

## Implementation / verification

Pure BoardSession owns atomic commands/revisions/history; EditorScene resolves Group bounds; controller owns normalized selection/previews and bounded spatial snap candidates. Shared action menu reuses themes. No pointer-move document writes. Clipboard owns one immutable forest and private original bytes (16MiB each/32MiB total); embedded font declarations remap safely, but portable files still only support existing bundled fonts. Failed staging may leave unattached originals; no new asset GC. Existing portable v1 and older local documents remain compatible.

`benchmark_results/advanced-editing/verification.json`: 91 distinct root host checks across integration/focused runs;39 distinct Chrome advanced checks. Additional17 agent session/frame regressions pass. Analysis clean. Real native restart retained Group; resize/rotation/Undo/Redo exercised. Real Chrome reload retained Group locks and copied original PNG/JPEG after Board switching. Widget reopen/portable checks are simulations, separately recorded. Screenshots are actual running apps.

Remaining: WB-0814 native mobile contextual/device testing; WB-0610 physical touch handle qualification; WB-0407/0408 physical modifier/IME checks. Native CUA modifier injection was unreliable (some chords reached plain-letter shortcuts); no hardware pass. CUA Chrome drags sometimes produced dots/no marquee; browser widget interaction tests pass, manual physical Chrome drag check still needed. M08/WB-0816 dense performance remains unverified; no benchmarks run. Wider platform PNG/project gateways and accessibility/device gates remain inherited backlog.

## Data / next

Original native Arabic board and12-element active user board were untouched. A new native test Board contains a transformed three-element Group. Chrome localhost8772 new advanced test Board has8 elements including pasted original PNG/JPEG and a locked Group; source two-image Board and older Frame test Board retained. Never clear profiles/containers/assets to release locks. If resuming after source hot reload, full browser Reload avoids old controller field state.

Next: review this editing milestone, then qualify physical Chrome/macOS shortcuts/drag and Android/iOS touch/IME; fix reproduced issues before unrelated features. Existing 10K requirement stays in Production Hardening.
