# Changelog

## v0.1.0-beta.4 — 2026-10-24

- Replace the Flutter template Windows icon with the existing Blanko brand at nine resolutions.
- Show the build number in the Windows title so downloaded packages can be identified.
- Require a real Windows Release check of enabled Files/export controls and acknowledged drawing/image persistence across two OS processes before packaging.
- Keep the existing Windows file support introduced in beta.3 and preserve the application-support directory identity and all Boards.

## v0.1.0-beta.3 — 2026-10-23

Includes the native platform and persistence fixes below, Android build code3, and a strict certificate check compatible with numbered, SDK-range and scheme-prefixed (`V3.0 Signer:`) labels. All signing identities must match the approved owner certificate; additional or unapproved signers remain rejected.

## v0.1.0-beta.2 — 2026-10-23

Candidate tag retained; not published. SDK37 changed signer output and the initial certificate parser failed closed before distribution.

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
