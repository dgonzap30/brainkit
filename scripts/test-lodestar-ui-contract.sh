#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$root/scripts/check-lodestar-ui-contract.sh"
fixtures="$root/scripts/fixtures/lodestar-ui-contract"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/lodestar-ui-contract-tests.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT

checks=0
failures=0

make_fixture() {
  local name="$1"
  local fixture_root="$scratch/$name"
  local ui="$fixture_root/Sources/LodestarUI"

  mkdir -p "$ui"
  cp "$fixtures/LodestarColor.valid.swift" "$ui/LodestarColor.swift"
  cp "$fixtures/LodestarMetrics.valid.swift" "$ui/LodestarMetrics.swift"
  printf '%s\n' "$fixture_root"
}

expect_status() {
  local label="$1"
  local expected="$2"
  shift 2

  checks=$((checks + 1))
  local output="$scratch/output-$checks"
  local actual

  if "$@" >"$output" 2>&1; then
    actual=0
  else
    actual=$?
  fi

  if [[ "$actual" -eq "$expected" ]]; then
    printf 'ok %d - %s\n' "$checks" "$label"
    return
  fi

  printf 'not ok %d - %s (expected %d, got %d)\n' \
    "$checks" "$label" "$expected" "$actual" >&2
  sed 's/^/  /' "$output" >&2
  failures=$((failures + 1))
}

clean_fixture="$(make_fixture 'clean explicit root')"

ordinary_import_fixture="$(make_fixture ordinary-import)"
cp "$fixtures/ForbiddenOrdinary.swift" \
  "$ordinary_import_fixture/Sources/LodestarUI/Forbidden.swift"

qualified_import_fixture="$(make_fixture qualified-import)"
cp "$fixtures/ForbiddenKindQualified.swift" \
  "$qualified_import_fixture/Sources/LodestarUI/Forbidden.swift"

attributed_import_fixture="$(make_fixture attributed-import)"
cp "$fixtures/ForbiddenAttributed.swift" \
  "$attributed_import_fixture/Sources/LodestarUI/Forbidden.swift"

access_import_fixture="$(make_fixture access-import)"
cp "$fixtures/ForbiddenAccessQualified.swift" \
  "$access_import_fixture/Sources/LodestarUI/Forbidden.swift"

comment_separated_import_fixture="$(make_fixture comment-separated-import)"
cp "$fixtures/ForbiddenCommentSeparated.swift" \
  "$comment_separated_import_fixture/Sources/LodestarUI/Forbidden.swift"

multiline_import_fixture="$(make_fixture multiline-import)"
cp "$fixtures/ForbiddenMultiline.swift" \
  "$multiline_import_fixture/Sources/LodestarUI/Forbidden.swift"

backticked_import_fixture="$(make_fixture backticked-import)"
cp "$fixtures/ForbiddenBackticked.swift" \
  "$backticked_import_fixture/Sources/LodestarUI/Forbidden.swift"

invalid_syntax_fixture="$(make_fixture invalid-syntax)"
cp "$fixtures/InvalidSyntax.swift" \
  "$invalid_syntax_fixture/Sources/LodestarUI/Invalid.swift"

swapped_fixture="$(make_fixture swapped-colors)"
cp "$fixtures/LodestarColor.swapped.swift" \
  "$swapped_fixture/Sources/LodestarUI/LodestarColor.swift"

comment_only_fixture="$(make_fixture comment-only-colors)"
cp "$fixtures/LodestarColor.comment-only.swift" \
  "$comment_only_fixture/Sources/LodestarUI/LodestarColor.swift"

unrelated_fixture="$(make_fixture unrelated-colors)"
cp "$fixtures/LodestarColor.unrelated.swift" \
  "$unrelated_fixture/Sources/LodestarUI/LodestarColor.swift"

block_comment_fixture="$(make_fixture block-comment-colors)"
cp "$fixtures/LodestarColor.block-comment.swift" \
  "$block_comment_fixture/Sources/LodestarUI/LodestarColor.swift"

multiline_string_fixture="$(make_fixture multiline-string-colors)"
cp "$fixtures/LodestarColor.multiline-string.swift" \
  "$multiline_string_fixture/Sources/LodestarUI/LodestarColor.swift"

real_rg="$(command -v rg)"

expect_status "clean candidate passes with default root" 0 "$gate"
expect_status "clean candidate passes with explicit root" 0 "$gate" "$root"
expect_status "minimal clean fixture passes" 0 "$gate" "$clean_fixture"
expect_status "ordinary forbidden import fails" 1 "$gate" "$ordinary_import_fixture"
expect_status "kind-qualified tabbed forbidden import fails" 1 \
  "$gate" "$qualified_import_fixture"
expect_status "attributed kind-qualified tabbed forbidden import fails" 1 \
  "$gate" "$attributed_import_fixture"
expect_status "access-qualified tabbed forbidden import fails" 1 \
  "$gate" "$access_import_fixture"
expect_status "comment-separated forbidden import fails" 1 \
  "$gate" "$comment_separated_import_fixture"
expect_status "multiline forbidden import fails" 1 \
  "$gate" "$multiline_import_fixture"
expect_status "backticked forbidden import fails" 1 \
  "$gate" "$backticked_import_fixture"
expect_status "Swift parser syntax error fails closed" 1 \
  "$gate" "$invalid_syntax_fixture"
expect_status "Swift parser execution error propagates" 2 \
  env PATH="$fixtures/swiftc-error-bin:$PATH" "$gate" "$clean_fixture"
expect_status "ripgrep execution error propagates" 2 \
  env PATH="$fixtures/rg-error-bin:$PATH" LODESTAR_REAL_RG="$real_rg" \
  "$gate" "$clean_fixture"
expect_status "swapped color literals fail" 1 "$gate" "$swapped_fixture"
expect_status "comment-only color literals fail" 1 "$gate" "$comment_only_fixture"
expect_status "unrelated color literals fail" 1 "$gate" "$unrelated_fixture"
expect_status "block-comment color declarations fail" 1 \
  "$gate" "$block_comment_fixture"
expect_status "multiline-string color declarations fail" 1 \
  "$gate" "$multiline_string_fixture"

if [[ "$failures" -ne 0 ]]; then
  printf '%d of %d contract-gate regressions failed\n' "$failures" "$checks" >&2
  exit 1
fi

printf 'all %d contract-gate regressions passed\n' "$checks"
