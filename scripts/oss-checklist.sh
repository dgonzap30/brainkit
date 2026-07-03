#!/usr/bin/env bash
# brainkit-oss-checklist.sh — OSS-boundary leak check for the BrainKit package
# (docs/architecture/oss-boundary-plan.md, E8-10).
#
# BrainKit is Apache-2.0 and consumed by third parties (external SwiftPM `url:`
# deps). This is a narrower, complementary check to tooling/lib/secret-scan.ts
# (which hunts generic API-key/private-key shapes across the whole repo): this
# one hunts Diego's-specific-infra leakage that a generic secret scanner would
# never flag because none of it is a "secret" by that definition — a Tailnet
# hostname or a literal /Users/dgz path isn't a credential, but it has no
# business in a public plugin SDK either.
#
# Scans only Sources/ and Contract/ (the two dirs that ship to consumers;
# Tests/ may reasonably reference local paths in fixtures set up for CI).
#
# NOTE ON LOCATION: this belongs conceptually to the BrainKit package, but
# `Packages/BrainKit` is a git submodule (gitlink) — git refuses to track any
# path under a registered submodule from the superproject ("fatal: Pathspec
# '...' is in submodule 'Packages/BrainKit'", verified 2026-07-03). It cannot
# be committed to lodestar at Packages/BrainKit/scripts/oss-checklist.sh from
# this branch. It lives here until copied into the BrainKit repo itself
# (a one-line follow-up next time that repo is touched, out of scope here).
#
# Usage:
#   scripts/brainkit-oss-checklist.sh                  # scans Packages/BrainKit
#   TARGET_DIR=/path/to/brainkit scripts/brainkit-oss-checklist.sh   # scan elsewhere
#     (e.g. against the BrainKit repo directly, once this script has moved there)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-$ROOT/Packages/BrainKit}"

if [[ ! -d "$TARGET_DIR/Sources" || ! -d "$TARGET_DIR/Contract" ]]; then
  echo "brainkit-oss-checklist: $TARGET_DIR has no Sources/ and Contract/ — is the submodule checked out?" >&2
  exit 1
fi

# Pattern -> human label. Grep -n so hits print file:line.
declare -a PATTERNS=(
  "LODESTAR_INGEST_TOKEN:ingest-token env var name"
  "LODESTAR_FRONT_DOOR_TOKEN:front-door token env var name"
  "[Bb]earer [A-Za-z0-9._-]{16,}:literal bearer token value"
  "[A-Za-z0-9-]+\\.ts\\.net:Tailnet (*.ts.net) hostname"
  "(^|[^0-9])100\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}:Tailscale CGNAT (100.x) IP"
  "/Users/dgz:Diego's local machine path"
  "~/\\.lodestar:local lodestar dotfile/state path"
)

found=0
for entry in "${PATTERNS[@]}"; do
  pattern="${entry%%:*}"
  label="${entry#*:}"
  hits="$(grep -rnE "$pattern" "$TARGET_DIR/Sources" "$TARGET_DIR/Contract" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    found=1
    echo "brainkit-oss-checklist: FOUND [$label] (pattern: $pattern)" >&2
    echo "$hits" | sed 's/^/  /' >&2
  fi
done

if [[ "$found" -ne 0 ]]; then
  echo "brainkit-oss-checklist: FAILED — infra-shaped strings found in the OSS boundary (Sources/, Contract/)" >&2
  exit 1
fi

echo "brainkit-oss-checklist: clean — no infra-shaped strings in $TARGET_DIR/{Sources,Contract}"
