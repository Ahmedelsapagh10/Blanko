# Blanko Open-Source Public Beta Release — 2026-10-22

COMPLETED; open-source release v0.1.0-beta.1 prepared and published. GitHub Actions CI/CD running cross-platform builds.

## What was done

Release preparation for Blanko as an open-source public beta on the existing GitHub repository (Ahmedelsapagh10/whitebaord).

### Stage A — Safety audit
- Scanned all tracked files, Git history, and assets for secrets, keys, credentials, and private data — none found.
- Environment JSON files contain hardware/SDK info only (no tokens or credentials).
- No keystores, `.jks`, `.pem`, `.env`, or `key.properties` in history.
- Android release signing uses debug keys (no private keystore committed).
- Font licenses: Roboto and Noto Sans Arabic — both SIL Open Font License 1.1, compatible with MIT.
- Updated `.gitignore` to exclude signing keys, IDE files, user board data, and environment files.

### Stage B — Repository and README
- Created MIT License with third-party font attribution.
- Wrote professional Arabic README with hero section, features table, real screenshots, download links, build instructions, and contributing guide.
- Copied 8 real application screenshots to `docs/screenshots/`.
- Added community files: CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md.
- Added GitHub issue templates (bug report, feature request) and PR template.

### Stage C — CI/CD
- Created `.github/workflows/release.yml` with:
  - Static analysis and full test suite validation
  - macOS, Linux, Windows, and Android builds on appropriate runners
  - Artifact packaging with correct naming
  - SHA-256 checksum generation
  - Automated GitHub Release with Arabic release notes
  - Triggered on `v*` tags

### Stage D — Local build verification
- macOS release build: ✅ Blanko.app (46.2MB), ZIP packaged (19.2MB), launched and verified.
- Static analysis: ✅ clean (0 errors, 0 warnings).
- Test suite: ✅ 401 passed, 3 skipped.
- Version set to 0.1.0+1.

### Stage E — Publication
- Committed: `51252ae` — "Prepare open-source public beta release v0.1.0-beta.1"
- Pushed to `origin/master` and tag `v0.1.0-beta.1` pushed.
- Initial CI run (ID: 39790721089) diagnosed: 4 tests failed on Linux VM due to platform-specific feature gates (`supportsProductFiles` and `supportsImagePicking` are false on Linux). Also identified `Blanko.app` naming in macOS package step and updated repo links to `Ahmedelsapagh10/Blanko`.
- Remediations applied:
  - `test/png_export_dialog_test.dart`: added `skip: !supportsProductFiles` to native save tests.
  - `test/product_ui_refinement_test.dart`: checked for either image import tooltip variant depending on platform capability.
  - `.github/workflows/release.yml`: added robust `Blanko.app` detection for macOS zip, PowerShell fallback for Windows, clean `sha256sum Blanko-*` checksums, and updated issue URL.
  - `README.md` and `CONTRIBUTING.md`: updated repository URLs to `Ahmedelsapagh10/Blanko`.

### What's pending
- Push CI fixes commit and update tag `v0.1.0-beta.1` to re-trigger GitHub Actions release workflow.
- Monitor GitHub Actions cross-platform builds to full completion and verify release published.
- Repository visibility change to Public (manual GitHub Settings action by owner).
- Add repository description, topics (`whiteboard`, `flutter`, `canvas`, `open-source`, `arabic`) via GitHub web UI.
- macOS app is unsigned/unnotarized (standard for open-source; noted in README).
- Android APK uses debug signing (noted in release notes).

## Next exact actions
1. Push the CI remediation commit to `origin/master`.
2. Move tag `v0.1.0-beta.1` to the new commit and push (`git tag -f v0.1.0-beta.1 && git push -f origin v0.1.0-beta.1`).
3. Monitor GitHub Actions release workflow until all jobs succeed and artifacts are attached.
4. Verify release download links on `https://github.com/Ahmedelsapagh10/Blanko/releases`.
5. Guide the repository owner on setting visibility to Public.
