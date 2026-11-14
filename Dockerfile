# syntax=docker/dockerfile:1
#
# Satu image dipakai dua container:
#   web      → node index.js         (port 3003)
#   mediamtx → mediamtx /app/mediamtx.container.yml
#
# ffmpeg ikut di image karena smart_transcode.sh memanggilnya saat transcode
# H.265 → H.264 (dipicu MediaMTX lewat runOnReady).

# ---------- Stage 1: dependency (native module dikompilasi di sini) ----------
FROM node:24-bookworm AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# Image full (bukan slim) dipakai supaya sqlite3/bcrypt bisa fallback ke
# node-gyp kalau prebuild untuk ABI Node 24 belum tersedia.
RUN npm ci --omit=dev --no-audit --no-fund

# ---------- Stage 2: runtime ----------
FROM node:24-bookworm-slim AS runtime
ENV NODE_ENV=production \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Jakarta \
    CCTV_DATA_DIR=/app/data

ARG MTX_VERSION=v1.20.0
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl bash tini procps \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; \
    base="https://github.com/bluenviron/mediamtx/releases/download"; \
    if ! curl -fsSL "${base}/${MTX_VERSION}/mediamtx_${MTX_VERSION}_linux_${arch}.tar.gz" -o /tmp/mediamtx.tgz; then \
      curl -fsSL "${base}/v1.16.1/mediamtx_v1.16.1_linux_${arch}.tar.gz" -o /tmp/mediamtx.tgz; \
    fi; \
    tar -xzf /tmp/mediamtx.tgz -C /usr/local/bin mediamtx; \
    rm -f /tmp/mediamtx.tgz; \
    chmod +x /usr/local/bin/mediamtx; \
    mediamtx --version

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Seed default (dipakai entrypoint saat volume masih kosong) + config khusus container
COPY docker/config.container.json /app/config.default.json
COPY docker/mediamtx.container.yml /app/mediamtx.container.yml
COPY docker/entrypoint.sh /entrypoint.sh

RUN set -eux; \
    chmod +x /entrypoint.sh /app/smart_transcode.sh /app/record_notify.sh; \
    mkdir -p /app/seed /app/data; \
    cp /app/cameras.db /app/seed/cameras.db; \
    rm -f /app/config.json /app/cameras.db /app/cameras.db-wal /app/cameras.db-shm /app/sessions.db*; \
    rm -rf /app/prototype /app/design-system /app/.git /app/.cindy-worktrees

EXPOSE 3003 8555 8856 8890 9123
VOLUME ["/app/data"]
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["node", "index.js"]
