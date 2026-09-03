# B1 — TELEGRAM Infisical migration (owner actions)

Date: 2026-09-03
Status: sidecar wired, awaiting Universal Auth identity creation

## What was already done (2026-09-03 09:18 UTC)

- `infisical secrets set` migrated `TELEGRAM_BOT_TOKEN_GUARDIAN` and `TELEGRAM_USER_ID`
  into vps-shared (workspace `98137933-832d-4f27-a1c6-7fc5e61f843a`), env `prod`,
  path `/openchamber/` — the canonical path per INFISICAL-STACK-20260902.md §per-container.
  Verified via length round-trip (46 chars BOT_TOKEN, 10 chars USER_ID, both match backup).
- Wrong path `/` got 2 duplicates written (gotcha: I read NR-9 wrong, should be `/openchamber/`).
  Cannot delete via CLI or API (doc gotcha #3 — "Blind index for project not found").
  The duplicates are benign: `infisical run --path /openchamber` only reads from `/openchamber/`.
- Created `infisical-agent/Dockerfile` + `agent-config.yaml` (same pattern as dashboard-b2b).
- Modified `docker-compose.yml`:
  - Removed `TELEGRAM_BOT_TOKEN_GUARDIAN` + `TELEGRAM_USER_ID` from plaintext env
  - Added `depends_on: infisical-agent` (sidecar healthcheck gates openchamber startup)
  - Wrapped `command:` in `sh -c "set -a; . /run/secrets/active.env; set +a; exec bun ..."` to source the sidecar output (env_file: cannot work because compose evaluates paths on the host, not inside the container)
  - Added `./secrets:/run/secrets:ro` bind mount
  - Added `infisical-agent` service definition (sidecar)

## What the owner must do (3 steps, ~5 min)

### 1. Create a Universal Auth identity in Infisical UI

URL: https://pipeline-vps-new.tailbbccd8.ts.net:8437
Path: Organization Settings → Access Control → Machine Identities → "Create Identity"

- Name: `openchamber-infisical-agent`
- Role: `Member` (read-only is enough)
- Auth Method: `Universal Auth`
- TTL: leave default (1h, automatic refresh)

After creation, go to the identity's page and click "Add Project Membership":
- Project: `vps-shared` (98137933-...)
- Environment: `prod`
- Path: `/openchamber/`
- Permission: `Read` only

### 2. Get the client-id and client-secret

In the identity page, click "Universal Auth" tab. The credentials are:
- CLIENT_ID
- CLIENT_SECRET

### 3. Save them on the host (paste via SSH or write directly)

The owner runs these on the VPS:

```bash
# Replace the placeholders created on 2026-09-03 09:41 UTC
# (currently 0 bytes, chmod 600)
nano /home/pipeline/pipeline/docker/infisical-agent-secrets/openchamber.client-id
# paste CLIENT_ID, save
nano /home/pipeline/pipeline/docker/infisical-agent-secrets/openchamber.client-secret
# paste CLIENT_SECRET, save
chmod 600 /home/pipeline/pipeline/docker/infisical-agent-secrets/openchamber.{client-id,client-secret}
```

## After the owner is done

The next automated session will:

```bash
cd /home/pipeline/pipeline/docker/openchamber
mkdir -p secrets
docker compose build infisical-agent
docker compose up -d infisical-agent
sleep 10
docker logs openchamber-infisical-agent --tail 30
# expect: "rendering template ... destination: /run/secrets/active.env"
cat secrets/active.env | head -5
# expect: 3 lines (TELEGRAM_BOT_TOKEN_GUARDIAN, TELEGRAM_USER_ID, OPENCHAMBER_UI_PASSWORD)

docker compose up -d --force-recreate openchamber
docker exec openchamber sh -c "cat /proc/7/environ | tr \\"\\0\\" \\"\\n\\" | grep ^TELEGRAM_BOT_TOKEN_GUARDIAN | head -c 10"
# expect: starts with "8206..."

# After verification, delete the plaintext backup:
shred -u /tmp/secrets-migration-20260903/TELEGRAM_GUARDIAN.bak
shred -u /tmp/secrets-migration-20260903/TELEGRAM_GUARDIAN.migrated.bak
rmdir /tmp/secrets-migration-20260903/

# Commit + push the openchamber fork
git add docker-compose.yml infisical-agent/
git commit -m "chore(openchamber): source TELEGRAM from Infisical sidecar (Phase 3.2)

Adds infisical-agent service using same sidecar pattern as dashboard-b2b.
Injects TELEGRAM_BOT_TOKEN_GUARDIAN and TELEGRAM_USER_ID from prod/openchamber/
at container startup via /run/secrets/active.env. Plaintext .env no longer
needed for these.

Backup: /tmp/secrets-migration-20260903/ (mode 0600). Will be deleted
once the wiring is verified end-to-end."
git push origin upgrade-v122
```
