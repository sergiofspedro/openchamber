#!/bin/sh
set -eu
LOCKS_DIR="/home/openchamber/.local/state/opencode/locks"
CURRENT_HOST="$(cat /etc/hostname 2>/dev/null || hostname)"
[ -d "$LOCKS_DIR" ] || exit 0
for lock in "$LOCKS_DIR"/*.lock; do
  [ -d "$lock" ] || continue
  meta="$lock/meta.json"
  [ -f "$meta" ] || continue
  lock_host=$(grep -o '"hostname":"[^"]*"' "$meta" | cut -d'"' -f4)
  if [ -n "$lock_host" ] && [ "$lock_host" != "$CURRENT_HOST" ]; then
    echo "[clear-stale-locks] removing stale lock from dead container $lock_host: $lock"
    rm -rf "$lock"
  fi
done
