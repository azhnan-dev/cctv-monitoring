#!/bin/bash
# Beri tahu web-app bahwa satu segmen rekaman selesai (dipanggil MediaMTX).
# APP_BASE_URL diisi lewat env container (mis. http://web:3003); default lokal.
APP_BASE_URL="${APP_BASE_URL:-http://localhost:3003}"
APP_PORT="${APP_PORT:-}"
if [ -n "$APP_PORT" ]; then
    APP_BASE_URL="http://127.0.0.1:${APP_PORT}"
fi

curl -sS -X POST \
    -H "Content-Type: application/json" \
    -d "{\"path\":\"${MTX_PATH}\", \"file\":\"${MTX_SEGMENT_PATH}\"}" \
    --max-time 5 \
    "${APP_BASE_URL%/}/api/recordings/notify" || true
