# synesterra-mobile
Standalone Flutter/Dart app for Synesterra on Android and iOS.

This repository is reserved for the native mobile app. The existing TypeScript web/PWA laboratory lives in [synesterra-web](https://github.com/KornelSzyszka/synesterra-web).

Current status: Flutter scaffold and CI only. The app logic and physical-device audio validation have not started yet.

## Documentation

- [Architecture](docs/architecture.md): module layout and dependency direction (diagram).
- [AGENTS.md](AGENTS.md): instructions for AI coding agents; [agent collaboration rules](docs/agents/README.md).
- [Testing and evidence levels](docs/testing.md).
- [docs/](docs/README.md): index, including where patterns, code documentation and charts belong.

Quality gates: format, analyze, test and a debug APK build run in [CI](.github/workflows/ci.yml); iOS is built on demand. Emulator runs and unit tests do not prove audio timing or behaviour on a physical phone.
