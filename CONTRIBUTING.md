# Contributing to Blanko

Thank you for considering contributing to Blanko! 🎨

## Getting Started

### Prerequisites

- **Flutter SDK** 3.41.x or later (stable channel)
- **Dart SDK** 3.11.x or later
- **Platform tools**: Xcode (macOS/iOS), Android SDK (Android), Visual Studio (Windows)

### Setup

```bash
git clone https://github.com/Ahmedelsapagh10/whitebaord.git
cd whitebaord
flutter pub get
flutter run -d macos    # or: -d chrome, -d windows, -d linux
```

### Running Tests

```bash
flutter test                       # All unit/widget tests
flutter analyze --no-fatal-infos   # Static analysis
```

## How to Contribute

### Reporting Bugs

- Use the [Bug Report](https://github.com/Ahmedelsapagh10/whitebaord/issues/new?template=bug_report.md) issue template
- Include: steps to reproduce, expected vs. actual behavior, platform/OS, Flutter version
- Attach screenshots or screen recordings when relevant

### Suggesting Features

- Use the [Feature Request](https://github.com/Ahmedelsapagh10/whitebaord/issues/new?template=feature_request.md) issue template
- Describe the problem your feature solves
- Keep suggestions focused and actionable

### Pull Requests

1. **Fork** the repository and create a feature branch from `master`
2. **Keep changes focused** — one feature or fix per PR
3. **Run tests and analysis** before submitting:
   ```bash
   flutter test
   flutter analyze --no-fatal-infos
   ```
4. **Write clear commit messages** describing what changed and why
5. **Update documentation** if your change affects user-facing behavior
6. Submit your PR with a clear description

### Code Style

- Follow existing project conventions and architecture
- Keep the dependency footprint minimal — no new packages without discussion
- Preserve the local-first, no-backend architecture
- Document non-obvious design decisions
- All code must pass `flutter analyze` with zero errors and zero warnings

### Architecture Notes

- **Document model**: Pure Dart geometry and transforms in `lib/src/document/` and `lib/src/geometry/`
- **Editor**: Canvas rendering and interaction in `lib/src/editor/`
- **Persistence**: Platform-specific storage in `lib/src/persistence/`
- **Viewport**: Camera and spatial indexing in `lib/src/viewport/` and `lib/src/spatial/`

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
