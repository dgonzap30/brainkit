# Changelog

All notable changes to BrainKit are documented here. Versioning follows [SemVer](https://semver.org); contract schema versions (`capture.v1`, `temper.v1`, …) evolve additively and are documented per release.

## [0.1.0] — 2026-07-03

Initial standalone release, extracted from the Lodestar monorepo (`Packages/BrainKit`) with full history.

### Products

- **BrainKit** — versioned contract DTOs and clients (`connector.v1`, `health.v1`, `ledger.v1`, `temper.v1`; `worklog.v1` fixture for cross-repo conformance), `BrainClient`/`BrainConnectorClient` push transports, golden contract fixtures under `Contract/fixtures/`.
- **LodestarPluginKit** — app-side integration kit for personal apps (Reach, Temper, Ledger, Rundown).

### Platforms

- iOS 17+, macOS 14+ (swift-tools 5.9).
