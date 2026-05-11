#!/usr/bin/env bash
# Minimal assertion helper for Smith script tests.
# Source from test files. All functions print FAIL on stderr and exit 1.

assert_eq() {
  local expected="$1" actual="$2" label="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL %s: expected %q got %q\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" label="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL %s: expected exit %s got %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL %s: %q does not contain %q\n' "$label" "$haystack" "$needle" >&2
    exit 1
  fi
}
