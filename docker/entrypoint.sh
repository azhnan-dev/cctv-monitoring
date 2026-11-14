#!/usr/bin/env bash
#
# Entrypoint bersama untuk container web dan mediamtx.
# Tugasnya: siapkan volume data (config.json, cameras.db, recordings), terapkan
# override dari ENV, lalu jalankan command container.
#
set -euo pipefail

DATA_DIR="${CCTV_DATA_DIR:-/app/data}"
SEED_DIR="/app/seed"

log() { printf '[entrypoint] %s\n' "$*"; }

mkdir -p "$DATA_DIR/recordings" "$DATA_DIR/ai_snaps"

# Inisialisasi volume cukup sekali, meski dua container start bersamaan.
(
  flock 9

  if [ ! -f "$DATA_DIR/config.json" ]; then
    cp /app/config.default.json "$DATA_DIR/config.json"
    log "config.json baru dibuat dari default"
  fi

  if [ ! -f "$DATA_DIR/cameras.db" ] && [ -f "$SEED_DIR/cameras.db" ]; then
    cp "$SEED_DIR/cameras.db" "$DATA_DIR/cameras.db"
    log "cameras.db di-seed dari default repo"
  fi

  # Override dari environment (tidak menimpa kalau ENV kosong)
  node - "$DATA_DIR/config.json" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
let changed = false;

const set = (path, value, onlyIfEmpty = false) => {
  if (value === undefined || value === '') return;
  const parts = path.split('.');
  let cur = cfg;
  for (let i = 0; i < parts.length - 1; i++) cur = cur[parts[i]] = cur[parts[i]] || {};
  const key = parts[parts.length - 1];
  if (onlyIfEmpty && cur[key]) return;
  if (cur[key] === value) return;
  cur[key] = value;
  changed = true;
};

set('server.session_secret', process.env.SESSION_SECRET);
set('server.public_base_url', process.env.PUBLIC_BASE_URL, true);
set('mediamtx.host', process.env.MEDIAMTX_HOST || 'mediamtx');
set('mediamtx.public_hls_url', process.env.MEDIAMTX_PUBLIC_HLS_URL || 'http://mediamtx:8856');
set('recording.storage_path', process.env.RECORDINGS_PATH || '/app/data/recordings');
set('server.session.sqlite_db', process.env.SESSION_DB || '/app/data/sessions.db');
set('server.session.sqlite_table', 'sessions');
if (process.env.RECORDING_RETENTION) set('recording.delete_after', process.env.RECORDING_RETENTION);

if (changed) {
  fs.writeFileSync(file, JSON.stringify(cfg, null, 4));
  console.log('[entrypoint] config.json diperbarui dari environment');
}
NODE
) 9>"$DATA_DIR/.init.lock"

# Path runtime (dipakai app; script bash tetap membaca ./config.json via symlink)
export CCTV_CONFIG_PATH="$DATA_DIR/config.json"
export CCTV_DB_PATH="$DATA_DIR/cameras.db"
export CCTV_DISABLE_AI="${CCTV_DISABLE_AI:-1}"

# Symlink supaya smart_transcode.sh / record_notify.sh menemukan file yang sama
[ -e /app/config.json ] || ln -s "$DATA_DIR/config.json" /app/config.json
[ -e /app/cameras.db ] || ln -s "$DATA_DIR/cameras.db" /app/cameras.db
[ -e /app/recordings ] || ln -s "$DATA_DIR/recordings" /app/recordings

log "siap: $(basename "$1") ${*:2}"
exec "$@"
