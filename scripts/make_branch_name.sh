#!/usr/bin/env bash
# Generate branch name: task/<key-lower>-<slug-from-summary>
# Slug: ASCII-transliterated, lowercased, non-alphanumeric collapsed to "-",
# capped at 40 chars, trailing hyphens stripped.
set -euo pipefail

KEY="${1:?usage: make_branch_name.sh <KEY> <SUMMARY>}"
SUMMARY="${2:?usage: make_branch_name.sh <KEY> <SUMMARY>}"

command -v iconv >/dev/null 2>&1 || { echo "make_branch_name.sh: iconv not found" >&2; exit 1; }

key_lower=$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]')

slug=$(printf '%s' "$SUMMARY" \
  | { iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE 2>/dev/null || true; } \
  | tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-40 \
  | LC_ALL=C sed -E 's/-+$//')

[[ -n "$slug" ]] || { printf 'make_branch_name.sh: summary produced empty slug\n' >&2; exit 1; }

printf 'task/%s-%s\n' "$key_lower" "$slug"
