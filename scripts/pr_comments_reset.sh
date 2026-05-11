#!/usr/bin/env bash
# Signal monitor_pr_comments.sh to reset its backoff cadence on its
# next cycle. The monitor checks for `.smith/state/pr-comments/kick`
# and, if present, sets quiet_cycles=0 and switches back to the active
# polling interval, then removes the file.
#
# Called by Smith after every `git push` (smith:pr's initial push and
# smith:pr-fix-mode's per-cycle pushes). A push may trigger new
# reviewer activity within minutes; we don't want the monitor sleeping
# at the 30-min backoff interval through the response window.
#
# Idempotent: touching the file multiple times in quick succession is
# harmless — the monitor consumes it on its next read regardless.
#
# Usage: bash pr_comments_reset.sh

set -uo pipefail

STATE_DIR=".smith/state/pr-comments"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/kick"
