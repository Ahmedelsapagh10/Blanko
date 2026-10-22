# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | ✅ Current beta    |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public issue** for security vulnerabilities
2. **Email**: Contact the maintainer directly through their [GitHub profile](https://github.com/Ahmedelsapagh10)
3. **Include**: A clear description of the vulnerability, steps to reproduce, and potential impact

## Scope

Blanko is a local-first application with no backend services, no authentication, and no cloud storage. The primary security considerations are:

- **Local file handling**: Board data and exported files are stored locally
- **Build artifacts**: Release binaries are built via GitHub Actions and published with SHA-256 checksums
- **Dependencies**: Minimal third-party package usage (Flutter SDK, path_provider, web)

## Response

We aim to acknowledge security reports within 48 hours and provide a fix or mitigation plan within 7 days for confirmed vulnerabilities.
