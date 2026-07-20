# Changelog

All notable changes to BrainKit are documented here. Versioning follows [SemVer](https://semver.org); contract schema versions (`capture.v1`, `temper.v1`, …) evolve additively and are documented per release.

## [0.5.0] — 2026-07-20

### Added

- **Agent-inbox steer/revision fields** (`BrainKit`) — `AgentInboxItemDTO` gains `revisesId`, `steerNote`, `revisionMode` (all optional; present when an item re-proposes an earlier one after a user steer note) and `WritePlan.payload` (`[String: JSONValue]`, best-effort decoded — malformed/absent payload falls back to empty, never drops the item).

### Fixed

- **Checklist action-needed icon** (`LodestarPluginKit`) — incomplete setup steps in `CapabilityChecklistView` now render a quiet open circle instead of an amber alarm badge. An unfinished setup step is a to-do, not a failure; amber is reserved for was-working-now-broken states per the Lodestar design language.

No breaking changes.

## [0.4.0] — 2026-07-16

### Added

- **LodestarUI** — new product: shared design kit for the phone apps (app UI overhaul U1). OLED palette tokens (`LodestarColor`), SF-only type ramp helpers (`LodestarType`), spacing/radius metrics (`LodestarMetrics`), and components `StatusPill`, `EmptyState`, `SettingsSection`, `LodestarCard`, `LockedField`.
- **Config-lock** (`LodestarPluginKit`) — per-field `userOverride` flags (`ProvisionedField`, `isOverridden`, `setOverridden`); `refreshFromBrain` skips overridden fields; `adoptBundleProvisioning` clears flags on adopt (redeploy wins). Additive; flags default false, so behavior is unchanged until an app's settings UI sets them.
- **EA client** (`BrainKit`, merged pre-tag) — `eaThreads(q:limit:)` search/limit, `eaRenameThread`, EA thread list/create/get/archive + SSE send (U0 T4).

No breaking changes.

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
