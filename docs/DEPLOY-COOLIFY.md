# Deploy ke Coolify (CT 120) — stack CCTV

Catatan hasil deploy nyata (2026-11-14). Semua langkah **lewat API**, tanpa klik dashboard.

## Identitas resource

| Item | Nilai |
|---|---|
| Project | `CCTV` — uuid `0wmhflxq9mwmv34crclf22vd`, environment `production` |
| Application | `cctv-monitoring` — uuid `uooau1orf3p1lcb5fr8lzolo` |
| Build pack | `dockercompose` (file `/docker-compose.yml` dari repo) |
| Akses | **http://10.111.111.3:4026** → container `3003` |
| Volume | `uooau1orf3p1lcb5fr8lzolo_cctv-data` → `/app/data` |
| Container | `web-…` + `mediamtx-…` (dari satu image) |

## Urutan create (yang berhasil)

```bash
TOK=$(cat ~/.coolify-token); B=http://10.111.111.3:8000/api/v1
H="Authorization: Bearer $TOK"

# 1. project
curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  -d '{"name":"CCTV"}' "$B/projects"

# 2. application (compose dari git)
curl -s -X POST -H "$H" -H "Content-Type: application/json" -d '{
  "project_uuid":"<project_uuid>",
  "environment_name":"production",
  "server_uuid":"k92rkbafyz7i5ve539ba0xab",
  "destination_uuid":"duai48zqzvs5oe93e5be1gpd",
  "git_repository":"https://github.com/azhnan-dev/cctv-monitoring",
  "git_branch":"main",
  "build_pack":"dockercompose",
  "docker_compose_location":"/docker-compose.yml",
  "name":"cctv-monitoring",
  "instant_deploy":false
}' "$B/applications/public"

# 3. env
curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  -d '{"key":"PUBLIC_BASE_URL","value":"http://10.111.111.3:4026"}' \
  "$B/applications/<app_uuid>/envs"

# 4. deploy + pantau
curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  -d '{"uuid":"<app_uuid>"}' "$B/deploy"
curl -s -H "$H" "$B/deployments/<deployment_uuid>" | jq -r .status
```

## Env yang dipakai

| Key | Nilai |
|---|---|
| `SESSION_SECRET` | random 48 karakter |
| `PUBLIC_BASE_URL` | `http://10.111.111.3:4026` |
| `RECORDING_RETENTION` | `7d` |
| `CCTV_DISABLE_AI` | `1` (di-set di compose) |

Compose juga memakai `${CCTV_ADMIN_USER}`/`${CCTV_ADMIN_PASS}` (opsional). Tanpa itu,
login memakai seed `docker/config.container.json` → **admin/admin** (ganti setelah login).

## Masalah yang muncul & perbaikannya

1. **Port 4025 bentrok** — saat deploy, `olt-monitor-v3` sudah memakai 4025
   (`Bind for 0.0.0.0:4025 failed: port is already allocated`). Coolify tidak
   memvalidasi bentrok untuk application/service. Stack dipindah ke **4026**.
   Cek dulu: `./scripts/check-ports.sh <port>`.
2. **MediaMTX v1.20 menolak API dari container lain** — balas 401. Perlu blok
   `authInternalUsers` di `docker/mediamtx.container.yml` (sudah ada di repo).
3. **Registrasi kamera gagal** karena app mengirim field `sourceProtocol` yang tidak
   dikenal MediaMTX v1.20 (POST `/v3/config/paths/add` → 400). Fix di `index.js`
   (commit `6d7419e`), hanya `rtspTransport` yang dikirim.
4. **`mediaMtxRequest()` fallback ke 127.0.0.1 pada HTTP error** (mis. 404 saat DELETE
   path yang belum ada) → kegagalan koneksi di fallback menandai MediaMTX
   "unreachable" dan menghentikan sync. Sekarang fallback hanya untuk error jaringan.

## Update berikutnya

```bash
git push origin main          # perubahan kode/compose
# lalu deploy ulang:
curl -s -X POST -H "Authorization: Bearer $(cat ~/.coolify-token)" \
  -H "Content-Type: application/json" -d '{"uuid":"uooau1orf3p1lcb5fr8lzolo"}' \
  http://10.111.111.3:8000/api/v1/deploy
```

Volume `cctv-data` (config.json, cameras.db, sessions.db, recordings/) tidak ikut
terhapus saat redeploy — sesi login tetap bertahan (sudah diverifikasi).
