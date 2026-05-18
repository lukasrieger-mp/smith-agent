#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/classify_platform.sh"

# Pure iOS -> reject (exit 0, stdout "ios")
got=$(echo '["iOS"]' | bash "$SCRIPT")
assert_eq "ios" "$got" "pure-ios"

# Pure Android -> accept (exit 0, stdout "android")
got=$(echo '["Android"]' | bash "$SCRIPT")
assert_eq "android" "$got" "pure-android"

# Shared/KMP -> accept (exit 0, stdout "kmp")
got=$(echo '["Shared/KMP"]' | bash "$SCRIPT")
assert_eq "kmp" "$got" "pure-kmp"

# Mixed Android + iOS -> "android" (Android wins; spec 6.7 "any subset containing Android/KMP/Shared -> accept")
got=$(echo '["iOS","Android"]' | bash "$SCRIPT")
assert_eq "android" "$got" "mixed-android-ios"

# Mixed iOS + Shared -> "kmp"
got=$(echo '["iOS","Shared/KMP"]' | bash "$SCRIPT")
assert_eq "kmp" "$got" "mixed-shared-ios"

# Empty array -> "unclear"
got=$(echo '[]' | bash "$SCRIPT")
assert_eq "unclear" "$got" "empty"

# Unknown component only -> "unclear"
got=$(echo '["Backend"]' | bash "$SCRIPT")
assert_eq "unclear" "$got" "unknown"

# "Multiplatform" marker alone -> "kmp"
got=$(echo '["Multiplatform"]' | bash "$SCRIPT")
assert_eq "kmp" "$got" "multiplatform-alone"

# Multiplatform + Android -> still kmp (kmp wins precedence)
got=$(echo '["Multiplatform","Android"]' | bash "$SCRIPT")
assert_eq "kmp" "$got" "multiplatform-and-android"

# Multiplatform + iOS -> kmp (kmp wins; not iOS-only)
got=$(echo '["iOS","Multiplatform"]' | bash "$SCRIPT")
assert_eq "kmp" "$got" "multiplatform-and-ios"

# Caller-merged input (components ∪ labels) tolerates duplicates
got=$(echo '["Android","iOS","Android"]' | bash "$SCRIPT")
assert_eq "android" "$got" "duplicates-tolerated"

# Malformed JSON -> non-zero exit
if echo 'not json' | bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should error on bad JSON" >&2; exit 1
fi

echo "PASS classify_platform.test.sh"
