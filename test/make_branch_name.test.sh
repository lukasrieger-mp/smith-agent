#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/make_branch_name.sh"

# basic happy path
got="$(bash "$SCRIPT" "APP-5485" "App Review-Dialog auf dem Home Screen")"
assert_eq "task/app-5485-app-review-dialog-auf-dem-home-screen" "$got" "happy-path"

# all-lowercase already
got="$(bash "$SCRIPT" "app-5485" "review dialog on home")"
assert_eq "task/app-5485-review-dialog-on-home" "$got" "already-lower"

# punctuation collapsed to single hyphen, leading/trailing stripped
got="$(bash "$SCRIPT" "APP-1" "  Fix  the   thing!!! Now???  ")"
assert_eq "task/app-1-fix-the-thing-now" "$got" "punctuation"

# truncated to 40 chars on the slug part
long="A very very very very very very very long summary that exceeds the cap"
got="$(bash "$SCRIPT" "APP-2" "$long")"
slug="${got#task/app-2-}"
[[ ${#slug} -le 40 ]] || { echo "FAIL: slug ${#slug}>40 for $got" >&2; exit 1; }
# no trailing hyphen after cut
[[ "$slug" != *- ]] || { echo "FAIL: trailing hyphen in $got" >&2; exit 1; }

# missing args -> non-zero exit
if bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should error on missing args" >&2; exit 1
fi

# German umlauts transliterated (iconv //TRANSLIT)
got="$(bash "$SCRIPT" "APP-3" "Größere Schrift für ältere Nutzer")"
assert_contains "$got" "task/app-3-gr" "umlaut"
[[ "$got" != *"ö"* ]] || { echo "FAIL: umlaut survived in $got" >&2; exit 1; }

# Empty-slug rejection: all-punctuation summary
if ( bash "$SCRIPT" "APP-9" "!!! ???" ) 2>/dev/null; then
  echo "FAIL: should error on empty slug" >&2; exit 1
fi

# Empty-slug rejection: all-non-ASCII with no iconv mapping
# (Use a string that produces empty slug after iconv+sed.)
if ( bash "$SCRIPT" "APP-10" "中文标题" ) 2>/dev/null; then
  echo "FAIL: should error on empty slug from non-ASCII" >&2; exit 1
fi

echo "PASS make_branch_name.test.sh"
