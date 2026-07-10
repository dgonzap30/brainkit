# Changelog

All notable changes to BrainKit are documented here. Versioning follows [SemVer](https://semver.org); contract schema versions (`capture.v1`, `temper.v1`, …) evolve additively and are documented per release.

## [0.3.0] — 2026-07-09

### Added

- **E9 zero-config provisioning:** `ProvisioningRecord` + `PluginConfig.adoptBundleProvisioning` (deploy-time bundle stamping → first-launch Keychain adoption), `GET /pairing/config` client + `PluginConfig.refreshFromBrain` (config authority inversion), AI proxy request builders (`aiMessagesRequest`, `capabilitiesReportRequest`) + shared `BrainAIState` typed offline states with banner, `CapabilityCatalog` + `CapabilityChecklistView` setup checklist. Additive; no breaking changes.

## [0.2.1] — 2026-07-03

### Fixed

- **`rundown.v1`** — `RundownTake.scriptId` is now `String?` (was non-optional), matching the app-side `Take.scriptId` on `TakesStore.swift` where `nil` denotes a freeform take with no backing script. Fixture + tests updated with a freeform-take case.

## [0.2.0] — 2026-07-03

### Added

- **`rundown.v1`** wire types (`RundownTake`, `RundownScript`, `RundownIngestRequest`, `RundownIngestOutcome`) and `BrainClient.ingestRundown(_:ingestToken:)` push extension, mirroring the `temper.v1` contract and error semantics (accepted / discarded / retryable throw). Golden fixture at `Contract/fixtures/rundown.v1.json`.

## [0.1.0] — 2026-07-03

Initial standalone release, extracted from the Lodestar monorepo (`Packages/BrainKit`) with full history.

### Products

- **BrainKit** — versioned contract DTOs and clients (`connector.v1`, `health.v1`, `ledger.v1`, `temper.v1`; `worklog.v1` fixture for cross-repo conformance), `BrainClient`/`BrainConnectorClient` push transports, golden contract fixtures under `Contract/fixtures/`.
- **LodestarPluginKit** — app-side integration kit for personal apps (Reach, Temper, Ledger, Rundown).

### Platforms

- iOS 17+, macOS 14+ (swift-tools 5.9).
