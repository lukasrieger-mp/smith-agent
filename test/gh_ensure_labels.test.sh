#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/assert.sh
source "${SCRIPT_DIR}/lib/assert.sh"

SCRIPT="${ROOT}/scripts/gh_ensure_labels.sh"

# Dry-run prints both expected gh label commands
got=$(SMITH_DRY_RUN_GH_ENSURE_LABELS=1 bash "$SCRIPT")
[[ "$got" == *"smith-authored"* ]] || { echo "FAIL: missing smith-authored line in: $got" >&2; exit 1; }
[[ "$got" == *"needs-human-attention"* ]] || { echo "FAIL: missing needs-human-attention line in: $got" >&2; exit 1; }
[[ "$got" == *"--color 8B7AB6"* ]] || { echo "FAIL: missing smith-authored color in: $got" >&2; exit 1; }
[[ "$got" == *"--color D93F0B"* ]] || { echo "FAIL: missing needs-human-attention color in: $got" >&2; exit 1; }

echo "PASS gh_ensure_labels.test.sh"
