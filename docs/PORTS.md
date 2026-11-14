# Registry Port — Coolify CT 120 (`10.111.111.3`)

Sumber data: `scripts/check-ports.sh` (API Coolify + `ss`/`docker ps` di server).
Terakhir diverifikasi: **2026-11-14**.

## Konvensi

- Akses aplikasi = **IP:port langsung** (`http://10.111.111.3:<port>`), bukan domain sslip.
- Service baru memakai rentang **402x**.
- Hanya port yang benar-benar perlu diakses dari luar yang dipublish. Port internal
  (database, API internal, HLS kalau sudah diproxy) tidak perlu dibuka.

## Terpakai

| Port | Pemilik | Keterangan |
|---|---|---|
| 22 | sistem | SSH |
| 25 | sistem | MTA lokal |
| 53 | sistem | DNS resolver |
| 80, 443 | `coolify-proxy` (traefik) | reverse proxy + halaman error |
| 3001 | `kuma` | uptime kuma |
| 4010 | `pos-test` | container uji (boleh dibebaskan) |
| 4020 | `pos-klinik-madan-medica` | app pos (internal 4000) |
| 4023 | `obsidian` | catatan tim (internal 3000) |
| 4024 | `hermes-agent` | agent (internal 9119) |
| 4025 | `olt-monitor-v3` | app olt-monitor (internal 5001) |
| 6001, 6002 | `coolify` | terminal/realtime |
| 8000 | `coolify` | dashboard |
| 8080 | `coolify-proxy` | proxy internal |
| 5432, 6379, 9000, 8443 | internal container | tidak dipublish |

## Rencana (belum deploy)

| Port | Rencana | Catatan |
|---|---|---|
| **4025** | `cctv-monitoring` (stack Docker Compose) | web app; RTSP 8555 & HLS 8856 **tidak** dipublish (MediaMTX menarik stream dari kamera, HLS lewat proxy `/cam_*` di app) |

## Cara pakai

```bash
./scripts/check-ports.sh              # inventory semua port + pemiliknya
./scripts/check-ports.sh 4025 4026    # cek port tertentu → BEBAS / TERPAKAI (exit 1 kalau terpakai)
```

Catatan penting: Coolify **tidak** memvalidasi bentrok port untuk application/service
(hanya database). Kalau bentrok, Docker menolak bind saat start dan container jadi
`Exited` — makanya cek dulu dengan script ini sebelum deploy.
