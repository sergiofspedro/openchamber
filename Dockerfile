# syntax=docker/dockerfile:1
FROM oven/bun:1.3.14 AS base
WORKDIR /app

FROM base AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY bun-patches ./bun-patches
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/electron/package.json ./packages/electron/
COPY packages/vscode/package.json ./packages/vscode/
COPY packages/mobile/package.json ./packages/mobile/
RUN bun install --frozen-lockfile --ignore-scripts

FROM deps AS builder
WORKDIR /app
COPY . .
RUN bun run build:web

FROM oven/bun:1.3.14 AS runtime
WORKDIR /home/openchamber

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  gcc \
  git \
  less \
  libc6-dev \
  nodejs \
  docker-cli \
  npm \
  openssh-client \
  python3 \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI -- flagged missing by `oh-my-opencode doctor`; agents need it for GitHub
# automation (issue/PR management) instead of shelling out to nothing.
RUN mkdir -p -m 755 /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# Playwright's Chromium system libraries (needs root/apt) — installed here so the actual
# browser binary can be downloaded later as the openchamber user without needing sudo.
# Confirmed real need 2026-07-30: agents doing browser-based visual QA had no Chrome
# available, retry-looped for 12+ minutes burning ~975K tokens in a single stuck subtask
# before the whole session had to be aborted. Baking this in avoids that entirely.
RUN npx --yes playwright install-deps chromium webkit firefox

# procps: o agente precisa de `free` para medir a memoria antes de decidir
# o tamanho de uma onda de subagentes.
RUN apt-get update && apt-get install -y --no-install-recommends procps && rm -rf /var/lib/apt/lists/*

# Replace the base image's 'bun' user (UID 1000) with 'openchamber'
# so mounted volumes with 1000:1000 ownership work correctly.
RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

# Switch to openchamber user
USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g opencode-ai@1.18.25

# Motores de browser (deps de sistema instaladas acima como root).
# WebKit e Firefox acrescentados 2026-08-27: o produto tem de correr em
# qualquer browser de computador, e sem os motores isso era uma afirmacao
# por verificar. Sem eles a sessao tinha de levantar um contentor efemero
# do playwright de cada vez que auditava o Safari.
RUN npm install -g playwright \
 && playwright install chromium webkit firefox \
 && npm install -g @playwright/mcp

# opencode-runtime-fallback: generic OpenCode model-invocation fallback plugin,
# staged rollout starting 2026-08-01 (see task-checkpoint / plan) — validated on a
# throwaway agent before being trusted on orchestrator/reviewer.
RUN npm install -g opencode-runtime-fallback

# Rust toolchain + fdx (FlowDeck's token-optimized CLI) + rtk (bash-output compressor) baked into
# the image, not installed post-hoc via docker exec — anything added to the container's writable
# layer after startup is lost on the next `docker compose` recreate (confirmed the hard way: gcc,
# rustc, cargo, and fdx all silently disappeared after an unrelated compose change triggered one).
ENV PATH="/home/openchamber/.cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
# Plain `cargo install rtk` pulls a name-colliding, unrelated crate (Rust Type Kit) from
# crates.io -- rtk-ai/rtk's own README warns about this. Install from the real source.
RUN cargo install --git https://github.com/rtk-ai/rtk --force
RUN git clone --depth 1 https://github.com/DVNghiem/FlowDeck.git /tmp/flowdeck-build \
  && cargo install --path /tmp/flowdeck-build/crates/fdx \
  && rm -rf /tmp/flowdeck-build

# uv/uvx (Python package runner) — needed to run the Serena MCP server (oraios/serena) and
# Token Savior (token-savior-recall) via `uvx`, both invoked from opencode.jsonc's mcp block.
# Same ephemeral-layer risk as Rust above, so baked in here rather than via docker exec.
ENV PATH="/home/openchamber/.local/bin:${PATH}"
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN uv tool install -p 3.13 serena-agent

# cloudflared 2026.3.0 - update digest explicitly when upgrading
COPY --from=cloudflare/cloudflared@sha256:6d91c121b803126f7a5344005d17a9324788fc09d305b6e2560ec6040a7ae283 /usr/local/bin/cloudflared /usr/local/bin/cloudflared

ENV NODE_ENV=production

COPY scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh
# clear-stale-locks.sh is ours, not vendored from OpenChamber upstream, so it survives
# OpenChamber version upgrades. Clears OpenCode locks orphaned by a container that died
# without releasing them (confirmed cause of a real deadlock incident 2026-07-27: a stale
# lock from a dead container silently hung every session needing it until manually found).
COPY scripts/clear-stale-locks.sh /home/openchamber/clear-stale-locks.sh

# apply-known-patches.sh reapplies hand-patches to third-party OpenCode plugin
# caches (~/.cache/opencode/packages, NOT a mounted volume) that get wiped on
# every container recreate/rebuild. Backgrounded from ENTRYPOINT below so it can
# poll for files that only appear ~60-120s into startup.
COPY scripts/apply-known-patches.sh /home/openchamber/apply-known-patches.sh

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

EXPOSE 3000

ENTRYPOINT ["sh", "-c", "sh /home/openchamber/clear-stale-locks.sh && sh /home/openchamber/apply-known-patches.sh & exec sh /home/openchamber/openchamber-entrypoint.sh \"$@\"", "--"]
