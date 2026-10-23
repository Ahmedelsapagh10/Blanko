# Changelog

## v0.1.0-beta.2 — 2026-10-23

- Fix Windows Board Library/reopening across native path separators without changing stored data.
- Enable Windows/Linux native image/project pickers and PNG/project file output.
- Bound macOS image/project reads before allocating full file contents.
- Use the owner's Android release certificate and verify its fingerprint before publication.
- Add real native-engine storage/editor/PNG integration checks and Release startup CI.

Android beta.1 used a different Debug certificate: export `.wboard` backups before any uninstall. Physical devices, full picker qualification, Apple notarization and wider Linux support remain open.

## v0.1.0-beta.1 — 2026-10-22

First public beta; source commit `2659d8a`.

- Infinite canvas, drawing/highlighter/erasers/shapes/arrows, text and sticky notes.
- Images, Frames, grouping, transforms, Undo/Redo and local autosave.
- PNG with uniform Fit and portable `.wboard` files on supported file platforms.
- System/Light/Dark themes, responsive desktop/mobile controls.
- MIT source, retained third-party notices, Arabic README and contribution guides.
- Release-mode bundles for macOS, Windows, Linux and Android with SHA-256 checksums.

Build success is separate from runtime qualification. Windows/Linux file pick/save is unavailable. Android is Debug-signed preview; macOS is ad-hoc signed and unnotarized. See [installation, backups and verification limits](docs/RELEASE.md).
