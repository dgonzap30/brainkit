# Lodestar plugin wire contract

The law that keeps the Swift apps (limbs) and the Bun brain agreeing on what crosses the wire,
**without a codegen toolchain**. BrainKit holds the canonical Swift DTOs; the brain holds hand-written
validators. This document + the golden fixtures are the bridge that proves they still match.

## Versioned namespaces

Every payload type is a frozen, versioned namespace: `health.v1`, `ledger.v1`, … The `schemaVersion`
string is the first thing a validator checks and the brain **hard-rejects** anything it doesn't
recognise (`unsupported schemaVersion`).

## Immutable once shipped

A shipped `vN` is **frozen**. You may never rename, retype, or repurpose a field in a shipped version —
a 6-month-old app build is still pushing `health.v1`, and it must keep working forever.

- **Additive, optional changes** are allowed in place: a new *optional* field that older clients omit
  and older brains ignore is backward+forward compatible (e.g. `declined` was added to a ledger
  transaction and decodes to `false` when absent).
- **Breaking changes** (remove/rename/retype a field, change a required field's meaning) ship as a
  **new namespace** `vN+1` *alongside* `vN`. Both validators live until every client has migrated.
  Never edit `vN` in place.

## Two directions

The contract governs both halves of the nervous system:

- **observer-IN** (app → brain): the limb pushes a snapshot to an INGEST-gated receiver
  (`POST /core/personal-apps/{health,ledger}/ingest`). Covered by `health.v1` / `ledger.v1` here.
- **connector-OUT** (brain → app): the limb pulls brain-authored writes from its outbox
  (`GET /core/personal-apps/{appId}/outbox`, see `BrainConnectorClient`). The outbox record envelope
  is `connector.v1` — its golden fixture + validator are a follow-up ticket (E3); listed here so the
  namespace is reserved and the direction is documented, not as shipped surface yet.

## Drift gate

For each shipped namespace there is one **canonical golden fixture** under
`Packages/BrainKit/Contract/fixtures/<ns>.json`, generated from the BrainKit encoder (so it is a real
on-wire payload, not hand-waved). The brain vendors a **byte-identical** copy under
`brain/contract/fixtures/` (it never checks out this package). Two conformance gates ride on them:

- **brain side** — `brain/src/contract.test.ts` parses each vendored fixture through the matching
  validator (`validateHealthPayload`, `validateLedgerPayload`) and asserts `ok: true` plus key fields.
- **Swift side** — `Packages/BrainKit/Tests/.../ContractFixtureTests` decodes each canonical fixture
  through the matching BrainKit DTO and asserts the values round-trip.

If either side drifts (a field renamed/retyped without a version bump), its gate goes red. Both run in
`tooling/gates.sh` (`==> contract conformance`).

## Field outline

### health.v1 — `HealthIngestRequest`
`schemaVersion` "health.v1" · `deviceId` string · `exportedAt` ISO-8601 string · `reason`
(observer|foreground|manual|backfill) · `days[]` · `workouts[]`.
- **day** — `day` "YYYY-MM-DD" (required) + optional metrics: `sleep{durationMin,remMin,deepMin,
  coreMin,awakeMin,inBedMin}`, `restingHeartRate`, `hrvMs`, `activeEnergyKcal`, `exerciseMin`, `steps`,
  `walkRunDistanceKm`, `vo2Max`, `respiratoryRate`, `spo2`, `bodyMassKg`, `mindfulMin`. Absent metrics
  are omitted (never `null`); a metric is always a finite, non-negative number.
- **workout** — `uuid`, `type`, `start`, `end` (non-empty strings), `durationMin` (number) required;
  `energyKcal`, `distanceKm`, `avgHeartRate` optional.

### ledger.v1 — `LedgerIngestPayload`
`schemaVersion` "ledger.v1" · `deviceId` string · `exportedAt` ISO-8601 string · `reason` string ·
`snapshot` · `transactions[]`.
- **snapshot** — `todayTotals` / `monthTotals` / `sourceCounts` (`[currency|source: number]` maps),
  `pendingCount` (number), `latestTransaction` (a transaction or null).
- **transaction** — `id` (UUID string), `dedupeKey`, `timestamp` (ISO-8601 string), `currency`,
  `merchant`, `cardName`, `source` (strings); `amount` (number); `pending`, `declined` (booleans;
  `declined` defaults to false when absent).

### Wire-type notes
- **Dates are strings.** A plain `JSONEncoder` encodes `Date` as a number; the brain validators require
  ISO-8601 *strings*. BrainKit therefore models `exportedAt`/`timestamp` as `String`, and the apps map
  `Date` ↔ ISO at their own boundary — so a plain encoder is always brain-valid.
- **Integer-valued doubles drop the decimal.** Swift encodes `48.0` as `48`; JSON has one number type,
  so the brain reads it back as a number and the Swift decoder reads `48` into a `Double`. Both fine.
