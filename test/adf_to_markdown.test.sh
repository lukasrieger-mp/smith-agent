#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/bin/adf_to_markdown.sh"
FIX="${SCRIPT_DIR}/fixtures/adf-sample.json"

# Pipe ADF JSON to the script; capture markdown output.
got=$(bash "$SCRIPT" < "$FIX")

# Headings rendered with ## / ###
assert_contains "$got" "## Hintergrundinformationen" "heading-2"
assert_contains "$got" "## User Story" "heading-user-story"

# Paragraph text appears
assert_contains "$got" "Bilder-sortieren-Screen" "paragraph-content"

# Strong/bold mark is preserved as **
assert_contains "$got" "**kurze**" "strong-mark"

# Bullet list rendered with leading -
assert_contains "$got" "- Bilder auswählen" "bullet-1"
assert_contains "$got" "- Buchart wählen" "bullet-2"

# Empty input -> empty output (no error)
got=$(printf '{"type":"doc","content":[]}' | bash "$SCRIPT")
assert_eq "" "$(echo -n "$got" | tr -d '\n')" "empty-doc"

# Invalid JSON -> non-zero exit
if echo 'not json' | bash "$SCRIPT" 2>/dev/null; then
  echo "FAIL: should reject non-JSON input" >&2; exit 1
fi

echo "PASS adf_to_markdown.test.sh"
