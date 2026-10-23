# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | ✅ Current beta    |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not open a public issue** with an exploit, private Board, or credentials.
2. Use [GitHub private vulnerability reporting](https://github.com/Ahmedelsapagh10/Blanko/security/advisories/new), enabled for this repository.
3. Include affected version/platform, reproduction steps and impact. Share a minimal synthetic project rather than personal data.

## Scope

Blanko is a local-first application with no backend services, no authentication, and no cloud storage. The primary security considerations are:

- **Local file handling**: Board data and exported files are stored locally
- **Build artifacts**: Release binaries are built via GitHub Actions and published with SHA-256 checksums
- **Dependencies**: Minimal third-party package usage (Flutter SDK, path_provider, web)

## Response

This is a community-maintained beta; response and remediation times are not guaranteed. The maintainer will triage private reports and coordinate disclosure.
