# Prototype Redesign — CCTV Monitoring

Prototype statis (HTML/CSS/JS, tanpa backend) untuk review arah redesign **sebelum**
menyentuh `views/*.ejs`.

## Cara buka

```bash
# cara 1 — langsung
xdg-open prototype/live.html

# cara 2 — lewat server lokal (lebih akurat untuk font & PWA)
python3 -m http.server 8099 --directory prototype
# lalu buka http://127.0.0.1:8099/live.html
```

Halaman: `live.html` (dashboard customer) · `admin.html` (panel admin) · `login.html`.

Tombol tema (ikon bulan/matahari) di topbar/rail — menyimpan pilihan di `localStorage`.
`screenshots/` berisi render 1440×1000 dan 390×844 dari ketiga halaman.

## Arah desain

Sumber: `design-system/cctv-monitoring/MASTER.md` (dari /ui-ux-pro-max, dial
`variance 5 / motion 4 / density 8`).

| Aspek | Keputusan |
|---|---|
| Gaya | **Minimalism / Swiss** — permukaan flat, border 1px, tanpa glow & tanpa glass blur |
| Mode | Dark-first, light mode tersedia sebagai token setara |
| Warna | Vault navy `#1E3A5F` (identitas/aktif), secure green `#059669` (**hanya** untuk status live/aksi utama), merah `#DC2626` (offline), amber `#D97706` (degradasi), slate netral |
| Tipografi | **Fira Sans** untuk UI/heading, **Fira Code** untuk semua angka (jam, bitrate, uptime, IP, ID kamera) |
| Spacing | ritme 4/8 px, dense (gap 8–16) |
| Radius | 4/6/8/10 px — tanpa sudut besar |
| Motion | 120–260 ms, hanya transisi state; `prefers-reduced-motion` dihormati |
| Ikon | Line SVG 1.75 px (placeholder konsisten). Di produksi ganti ke **Phosphor** `<i class="ph ph-*">`; emoji tidak dipakai sebagai ikon struktural |

Alasan deviasi dari rekomendasi font: design-system menyarankan Fira Code untuk heading.
Untuk layar operator yang dibaca dari jarak jauh, heading pakai Fira Sans (lebih lega),
Fira Code dipakai khusus untuk data numerik.

## Yang berubah per layar

### 1. Dashboard customer (`live.html`) ← `views/index.ejs`
| Sekarang | Prototype |
|---|---|
| Topbar penuh: tab, jam, tanggal, emoji cuaca, 3 tombol tema | Topbar 56px: brand, pencarian, status pill `7/8 online`, jam mono, preset grid, tema, user |
| Nav ganda (tab atas + bottom nav 5 item + toggle sidebar) | **Satu** rail ikon 56px di desktop; bottom nav 4 item di mobile |
| Sidebar kamera 420px dengan kartu besar | Drawer 300px: pencarian, filter chip dengan jumlah, list padat + status + "terakhir aktif" |
| Kamera offline = kotak hitam + titik merah | Empty state: ikon, teks alasan, waktu terakhir, tombol "Coba lagi" |
| Grid preset hanya desktop, tak bisa diakses keyboard | Tile fokusabel, Enter/Space untuk perbesar, Esc tidak diperlukan karena toggle, `aria-expanded` |
| Overlay aksi muncul hanya saat hover | Aksi muncul saat hover **dan** `focus-within` (keyboard) |
| Status hanya warna | Selalu ikon + teks ("Live", "Offline", "Bitrate rendah") |

### 2. Panel admin (`admin.html`) ← `views/admin*.ejs` + `partials/admin_sidebar.ejs`
- Sidebar 236px berkelompok (Operasi / Kamera & Media / Manajemen / Log & Notifikasi),
  item aktif = navy + garis aksen 2px, badge jumlah; bisa diciutkan jadi rail 60px.
- Header halaman: breadcrumb, judul, deskripsi, aksi utama jelas (Sinkron kamera / Tambah kamera).
- 4 KPI: total kamera, online (x/y), storage %, alert hari ini — angka tabular.
- Tabel "Kesehatan kamera": sticky header, kolom bitrate/latensi/terakhir aktif, hover row,
  status ikon+teks, aksi per baris. Di mobile tabel scroll di dalam kartu.
- Panel samping: bar chart storage 7 hari, meter retensi, list alert dengan severity.

### 3. Login (`login.html`) ← `views/login.ejs`
- Split layout: panel kiri brand + 3 angka kunci + status live (tanpa carousel), kanan form 380px.
- Error summary `role="alert"` yang difokus saat submit gagal, error inline per kolom,
  toggle password dengan `aria-pressed`, "ingat perangkat", tautan bantuan.
- Tidak ada animasi pulse pada pesan error (mengganggu & tidak aksesibel).

## Aturan yang sudah diterapkan

- Kontras teks ≥ 4.5:1 di kedua tema (pasangan token dihitung, bukan diasumsikan).
- Fokus keyboard selalu terlihat (`outline` 2px, offset 2px), `scroll-padding-top` mencegah
  fokus tertutup topbar sticky.
- Status tidak pernah hanya warna → ikon + teks.
- Target sentuh di mobile: kontrol utama 40–44 px, bottom nav 56 px, tile controls 36 px.
- `prefers-reduced-motion` mematikan semua transisi/animasi non-esensial.
- Safe area iPhone dihormati (`env(safe-area-inset-bottom)` pada bottom nav).
- Tidak ada overflow horizontal di 1440/1024/390 px (diukur headless, semua 0 px).

## Keterbatasan prototype (sengaja)

- Data statis; HLS/video hanya permukaan tiruan (`.tile__feed`).
- Tab "Peta", halaman lain, dan form tambah kamera belum dirancang.
- Preset grid 3×3/4×4 di prototype hanya mengubah kolom, bukan memindah kamera.
- Di mobile, preset grid & pencarian disembunyikan (rencananya lewat bottom-sheet "Tampilan").
- Light mode belum direview secara visual (hanya verifikasi kontras token).

## Rencana port ke aplikasi (setelah disetujui)

1. **Fondasi**: `public/css/tokens.css` + `public/css/app.css` (dari `prototype/assets/*`),
   Tailwind config `theme.extend` memetakan token → util (`bg-surface`, `text-muted`, dst).
   Hapus `cdn.tailwindcss.com` bertahap setelah build CSS stabil.
2. **Shell**: `partials/app_shell.ejs` (rail/sidebar + topbar + bottom nav) dipakai
   `index.ejs` dan semua `admin_*.ejs`; logika sidebar lama di `admin_sidebar.ejs` dipindah.
3. **Player**: komponen tile `partials/camera_tile.ejs`, atribut `data-state` diisi dari
   status MediaMTX (sudah tersedia di `/api/p2p/stream-status` & `/v3/paths/list`).
4. **Admin**: `admin_dashboard.ejs` ditulis ulang memakai komponen kartu/tabel baru.
5. **Login**: `login.ejs` diganti, `password-toggle.js` lama dipensiunkan.

## Pertanyaan yang perlu dijawab sebelum port

1. Setuju arah **dark-first + Swiss/flat** ini, atau mau tetap ada sentuhan glass/glow?
2. Nama brand di topbar: pakai `site.title` dari config (sekarang "CCTV Alijaya")?
3. Warna aksen: tetap **emerald/green** (sekarang) atau pindah ke biru untuk "aman/tenang"?
4. Bottom nav mobile: 4 item (Live, Peta, Rekaman, Akun) atau tetap 5 dengan "Lapor"?
5. Panel admin: sidebar berkelompok seperti ini atau tetap flat seperti sekarang?

## Status implementasi (diterapkan ke aplikasi)

| Prototype | Implementasi |
|---|---|
| `live.html` | `views/index.ejs` — topbar token, sidebar 300px, bottom nav, tile + overlay status/AI, empty state |
| `admin.html` | `views/admin_dashboard.ejs` + `partials/admin_header.ejs`, `partials/admin_sidebar.ejs` |
| `login.html` | `views/login.ejs` |
| `assets/tokens.css` | `public/css/tokens.css` |
| `assets/components.css` | `public/css/ui.css` (semua kelas diberi prefiks `ui-`) |
| — | `views/partials/theme_head.ejs` (head bersama: font, Tailwind config token, tema anti-flash) |

Logika HLS di `views/index.ejs` tidak diubah: setiap baris yang memuat `hls`/`m3u8`/`cam_`
identik dengan versi sebelum redesign (diverifikasi via diff).
