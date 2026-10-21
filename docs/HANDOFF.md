# Blanko handoff

2026-10-20. Assigned Frames→PNG→portable product work implemented; **105/275 checked**. Stop for review. Commit/push status in delivery/Git log. Existing UI, boards, assets and histories retained; no package/SDK upgrade. Native user-selected sandbox entitlement changes read-only→read-write for explicit Save panels.

Resume2026-10-21: final rotated handles included in25host+25Chrome passing checks; fresh analysis clean. Fresh normal Chrome restored saved Frames and keyboard F created a ContainerFrame without diagnostics. Menu-driven ExportFrame CUA drag remains inconclusive, so WB-0712 stays open; no physical input pass. All failed experiments were removed. Complete feature handoff/push; no further milestone work until review.

## Use

`flutter run -d macos`

`flutter run -d web-server --web-port=8772 --web-hostname=localhost`

More tools→Frame/Export frame, drag a rectangle; Select its border. Frame properties edits label/canvas size/output pixels atomically. Select artwork→Place in frame chooses membership or detach, preserving world position. Move parent with children; corner resize changes its rectangle, never scales children. Editing remains unclipped. Undo/Redo session-only, committed edits autosave.

Header Files & export→Export PNG: viewport/named Export Frame, solid canvas color or transparency, HD/4K/custom pixels. Save As .wboard includes original image assets; Import creates a new local board and remapped assets without replacing the current board. Local autosave target remains independent of the project file.

## Evidence and limits

`benchmark_results/frames-export/verification.json` lists exact files/checks/real screenshots.71host/62Chrome integration passes(1native-only skip), extra contract/rotated checks and clean analysis. Actual macOS native save/open panels and restart, Chrome downloaded files and reload, bidirectional project transfer verified. Real4K PNGs inspected; no performance claim.

WB-0712 stays unchecked: repeated native-automation Chrome draw gestures were inconsistent despite passing Chrome widgets and real creation during diagnosis. Do a physical Chrome Frame-create smoke/reproduce before checking it; Frame properties/movement/export/reload work in real Chrome. Native CUA text injection remains unreliable; do not infer a native IME pass. All temporary diagnostics removed.

Portable v1 is bounded uncompressed JSON/base64+CRC32, not ZIP; no extraction/traversal/bomb path.64MiB file/32MiB originals total/16MiB each; declared+actual image dimensions checked,64M original pixels max. Only existing bundled editor font references supported; custom/font assets/SHA256 declarations/newer versions reject safely. No incompatible local schema migration; old Frame records read without new optional fields, old strict readers reject new fields safely. Failed staged imports may leave unattached originals; no asset GC.

PNG max8192side/16M pixels/96MiB retained decoded images. Web needs owned CPU pixel transfer for offscreen image fidelity. Web helper may transiently decode full originals; GPU/codec/output peak memory and device time remain unqualified. Selection/custom-area export beyond frames, tiling, custom fonts, migrations and other native file platforms remain backlog.

## Data / next

Normal native store unchanged; Arabic34-element user board still present. Native separate Frame test board4elements and Chrome-imported2-image board preserved. Chrome test profile localhost8772 imported Frame board has additional diagnostic-created valid Frames; original2-image board remains independent. Original8770/8771/etc stores untouched. Own temporary output files under /private/tmp/blanko-native-*; browser files Untitled board*.png/.wboard in Downloads. Do not clear profiles/containers to release locks; full page reload after debug restart releases old page locks.

Next: physical Chrome drawing qualification, then remaining platform file gateways and format/device certification. Keep dense/stress hardening separate; no speculative benchmark restart.
