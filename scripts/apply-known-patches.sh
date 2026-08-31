#!/bin/sh
# Reapplies patches to third-party OpenCode plugins whose cache
# (~/.cache/opencode/packages) is NOT a mounted volume and gets wiped on
# every container recreate/rebuild. Runs backgrounded from ENTRYPOINT;
# polls because the target file doesn't exist until the embedded opencode
# server resolves plugins, ~60-120s into container startup.
set -u

FLOWDECK_FILE="/home/openchamber/.cache/opencode/packages/@dv.nghiem/flowdeck@0.7.0-alpha.4/node_modules/@dv.nghiem/flowdeck/dist/index.js"

i=0
found=0
while [ "$i" -lt 60 ]; do   # 60 x 5s = 5 min ceiling
  if [ -f "$FLOWDECK_FILE" ]; then
    found=1
    if grep -q 'new LoopDetector(undefined, appLog)' "$FLOWDECK_FILE"; then
      sed -i 's/new LoopDetector(undefined, appLog)/new LoopDetector({ enabled: false }, appLog)/' "$FLOWDECK_FILE"
      echo "[apply-known-patches] patched flowdeck LoopDetector"
    else
      echo "[apply-known-patches] flowdeck already patched (or upstream changed) - no-op"
    fi
    break
  fi
  i=$((i + 1))
  sleep 5
done
[ "$found" -eq 0 ] && echo "[apply-known-patches] flowdeck file never appeared after 5min - check plugin still pinned/present" >&2

exit 0
