#!/usr/bin/env bash
set -euo pipefail

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$script_root}"
ui="$root/Sources/LodestarUI"
contract_filter="$script_root/scripts/lodestar-ui-contract.jq"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/lodestar-ui-contract.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT

parse_source() {
  local source="$1"
  local ast="$2"
  local status

  if swiftc -frontend -dump-parse -dump-ast-format json "$source" >"$ast"; then
    :
  else
    status=$?
    printf 'check-lodestar-ui-contract: Swift parser failed with status %d for %s\n' \
      "$status" "$source" >&2
    return "$status"
  fi

  if jq -e 'type == "object" and ._kind == "source_file"' "$ast" \
    >/dev/null; then
    return 0
  else
    status=$?
  fi

  printf 'check-lodestar-ui-contract: invalid Swift parser output (jq status %d) for %s\n' \
    "$status" "$source" >&2
  if [[ "$status" -eq 1 ]]; then
    return 2
  fi
  return "$status"
}

reject_forbidden_imports() {
  local ast="$1"
  local source="$2"
  local status

  if jq -e \
    '[.. | objects | select(._kind? == "import_decl") | .module_path[0]?]
      | any(. == "BrainKit" or . == "LodestarPluginKit")' \
    "$ast" >/dev/null; then
    printf 'check-lodestar-ui-contract: forbidden module import in %s\n' \
      "$source" >&2
    return 1
  else
    status=$?
  fi

  if [[ "$status" -eq 1 ]]; then
    return 0
  fi

  printf 'check-lodestar-ui-contract: jq import check failed with status %d for %s\n' \
    "$status" "$source" >&2
  return "$status"
}

require_ast_contract() {
  local contract="$1"
  local container="$2"
  local name="$3"
  local value="$4"
  local ast="$5"
  local source="$6"
  local status

  if jq -e \
    --arg contract "$contract" \
    --arg container "$container" \
    --arg name "$name" \
    --arg value "$value" \
    -f "$contract_filter" \
    "$ast" >/dev/null; then
    return 0
  else
    status=$?
  fi

  if [[ "$status" -eq 1 ]]; then
    printf 'check-lodestar-ui-contract: required parsed declaration %s.%s missing in %s\n' \
      "$container" "$name" "$source" >&2
  else
    printf 'check-lodestar-ui-contract: jq declaration check failed with status %d for %s\n' \
      "$status" "$source" >&2
  fi
  return "$status"
}

require_match() {
  local pattern="$1"
  local path="$2"
  local status

  if rg -q "$pattern" "$path"; then
    return 0
  else
    status=$?
  fi

  if [[ "$status" -eq 1 ]]; then
    printf 'check-lodestar-ui-contract: required contract missing in %s\n' "$path" >&2
  else
    printf 'check-lodestar-ui-contract: ripgrep failed with status %d for %s\n' \
      "$status" "$path" >&2
  fi
  return "$status"
}

reject_matches() {
  local pattern="$1"
  local path="$2"
  local status

  if rg -n --glob '*.swift' "$pattern" "$path"; then
    printf 'check-lodestar-ui-contract: forbidden contract match in %s\n' "$path" >&2
    return 1
  else
    status=$?
  fi

  if [[ "$status" -eq 1 ]]; then
    return 0
  fi

  printf 'check-lodestar-ui-contract: ripgrep failed with status %d for %s\n' \
    "$status" "$path" >&2
  return "$status"
}

swift_files="$scratch/swift-files"
if rg --files --glob '*.swift' "$ui" >"$swift_files"; then
  :
else
  status=$?
  printf 'check-lodestar-ui-contract: unable to enumerate Swift sources (rg status %d) in %s\n' \
    "$status" "$ui" >&2
  exit "$status"
fi

if [[ ! -s "$swift_files" ]]; then
  printf 'check-lodestar-ui-contract: no Swift sources found in %s\n' "$ui" >&2
  exit 1
fi

color_ast=""
metrics_ast=""
index=0
while IFS= read -r source; do
  ast="$scratch/ast-$index.json"
  parse_source "$source" "$ast"
  reject_forbidden_imports "$ast" "$source"

  case "$source" in
    "$ui/LodestarColor.swift") color_ast="$ast" ;;
    "$ui/LodestarMetrics.swift") metrics_ast="$ast" ;;
  esac
  index=$((index + 1))
done <"$swift_files"

if [[ -z "$color_ast" || -z "$metrics_ast" ]]; then
  printf 'check-lodestar-ui-contract: required token source files missing in %s\n' \
    "$ui" >&2
  exit 1
fi

require_match \
  '^[[:space:]]*public[[:space:]]+static[[:space:]]+let[[:space:]]+surface[[:space:]]*=[[:space:]]*Color\(lodestarHex:[[:space:]]*0x0D0D0E\)[[:space:]]*$' \
  "$ui/LodestarColor.swift"
require_match \
  '^[[:space:]]*public[[:space:]]+static[[:space:]]+let[[:space:]]+accent[[:space:]]*=[[:space:]]*Color\(lodestarHex:[[:space:]]*0xA78BFA\)[[:space:]]*$' \
  "$ui/LodestarColor.swift"
require_match \
  '^[[:space:]]*public[[:space:]]+static[[:space:]]+let[[:space:]]+primaryControlHeight[[:space:]]*:[[:space:]]*CGFloat[[:space:]]*=[[:space:]]*44[[:space:]]*$' \
  "$ui/LodestarMetrics.swift"

require_ast_contract color LodestarColor surface 0x0D0D0E \
  "$color_ast" "$ui/LodestarColor.swift"
require_ast_contract color LodestarColor accent 0xA78BFA \
  "$color_ast" "$ui/LodestarColor.swift"
require_ast_contract integer LodestarMetrics primaryControlHeight 44 \
  "$metrics_ast" "$ui/LodestarMetrics.swift"

reject_matches \
  'URLSession|UserDefaults|Keychain|ModelContext|Analytics' \
  "$ui"
