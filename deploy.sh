#!/usr/bin/env bash
#
# deploy.sh — deploy / update CCTV Monitoring ke VPS dalam satu perintah.
#
#   ./deploy.sh            # dari workstation: push commit lokal lalu update server
#   ./deploy.sh --check    # hanya cek kesehatan server (tanpa mengubah apa pun)
#   ./deploy.sh --local    # jalankan langsung di server (git pull + restart)
#
# Opsi:
#   --no-push              jangan push commit lokal, langsung update server
#   -h, --help             tampilkan bantuan ini
#
# Env (opsional):
#   DEPLOY_HOST   host SSH tujuan        (default: cct101)
#   DEPLOY_DIR    path aplikasi di VPS   (default: /opt/cctv-monitoring)
#   DEPLOY_BRANCH branch yang dipakai    (default: main)
#   DEPLOY_PORT   port web app           (default: 3003)
#   DEPLOY_USER   user ssh               (default: user ssh config)
#
set -euo pipefail

HOST="${DEPLOY_HOST:-cct101}"
REMOTE_DIR="${DEPLOY_DIR:-/opt/cctv-monitoring}"
BRANCH="${DEPLOY_BRANCH:-main}"
PORT="${DEPLOY_PORT:-3003}"
SSH_USER_ARG="${DEPLOY_USER:-}"

MODE="deploy"
DO_PUSH=1
RUN_LOCAL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE="check" ;;
        --local)   RUN_LOCAL=1 ;;
        --no-push) DO_PUSH=0 ;;
        -h|--help) awk 'NR>2 && /^#/ { sub(/^# ?/, ""); print; next } NR>2 { exit }' "$0"; exit 0 ;;
        *) printf 'opsi tidak dikenal: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_DIM=""; C_OFF=""
fi
info() { printf '%s==>%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s!!%s %s\n'  "$C_YEL" "$C_OFF" "$*"; }
die()  { printf '%sxx%s %s\n'  "$C_RED" "$C_OFF" "$*" >&2; exit 1; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }

# ---------------------------------------------------------------------------
# Skrip yang dijalankan di server (dikirim lewat `bash -s`, tanpa file sementara)
# ---------------------------------------------------------------------------
REMOTE_SCRIPT=$(
cat <<'REMOTE'
set -euo pipefail

cd "$R_DIR" || { echo "xx direktori tidak ada: $R_DIR" >&2; exit 1; }
[ -d .git ] || { echo "xx bukan checkout git: $R_DIR" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

http_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${R_PORT}/login" 2>/dev/null || echo 000
}

health() { [ "$(http_code)" = "200" ]; }

if [ "$R_MODE" = "check" ]; then
    printf 'head      : %s\n' "$(git log --oneline -1)"
    printf 'branch    : %s (origin/%s)\n' "$(git rev-parse --abbrev-ref HEAD)" "$R_BRANCH"
    printf 'services  : %s\n' "$(systemctl is-active mediamtx cctv-web 2>/dev/null | tr '\n' ' ')"
    printf 'http      : %s (http://127.0.0.1:%s/login)\n' "$(http_code)" "$R_PORT"
    printf 'disk      : %s\n' "$(df -h / | awk 'NR==2{print $4" free of "$2}')"
    printf 'memory    : %s\n' "$(free -m | awk 'NR==2{print $3"MB used / "$2"MB"}')"
    health || { echo "xx health check gagal (/login bukan 200)" >&2; exit 1; }
    exit 0
fi

BEFORE=$(git rev-parse --short HEAD)
LOCK_BEFORE=$(sha256sum package-lock.json 2>/dev/null | cut -d' ' -f1 || echo none)

if [ -n "$(git status --porcelain)" ]; then
    echo "catatan: ada perubahan lokal di server (dilindungi skip-worktree), tidak ditimpa:"
    git status --porcelain | sed 's/^/  /'
fi

git fetch --quiet origin "$R_BRANCH"
if ! git merge --ff-only "origin/$R_BRANCH" >/dev/null 2>&1; then
    echo "xx update tidak bisa fast-forward. Selesaikan dulu di server:" >&2
    echo "   cd $R_DIR && git status && git log --oneline --graph -5" >&2
    exit 1
fi
AFTER=$(git rev-parse --short HEAD)

NEED_INSTALL=0
if [ "$BEFORE" = "$AFTER" ]; then
    echo "kode sudah versi terbaru: $AFTER"
else
    echo "kode diperbarui: $BEFORE -> $AFTER"
    CHANGED=$(git diff --name-only "$BEFORE" "$AFTER" 2>/dev/null || true)
    echo "$CHANGED" | sed '/^$/d' | sed 's/^/  /'
    echo "$CHANGED" | grep -qE '^package(-lock)?\.json$' && NEED_INSTALL=1
fi
LOCK_AFTER=$(sha256sum package-lock.json 2>/dev/null | cut -d' ' -f1 || echo none)
[ "$LOCK_BEFORE" != "$LOCK_AFTER" ] && NEED_INSTALL=1

if [ "$NEED_INSTALL" = 1 ]; then
    echo "memasang dependensi: npm install --omit=dev"
    npm install --omit=dev --no-audit --no-fund
fi

if [ "$BEFORE" != "$AFTER" ] || [ "$NEED_INSTALL" = 1 ]; then
    echo "restart service: mediamtx cctv-web"
    $SUDO systemctl restart mediamtx cctv-web || { echo "xx gagal restart service" >&2; exit 1; }
    for _ in $(seq 1 30); do
        health && break
        sleep 1
    done
fi

if health; then
    echo "ok: $(git log --oneline -1) — http://127.0.0.1:${R_PORT}/login 200"
else
    echo "xx health check gagal (/login bukan 200). Log terakhir:" >&2
    journalctl -u cctv-web -n 30 --no-pager >&2 || true
    exit 1
fi
REMOTE
)

run_remote() {
    local mode="$1"
    local target_dir="$2"
    local prelude
    prelude="R_MODE=$(printf '%q' "$mode") R_DIR=$(printf '%q' "$target_dir") R_BRANCH=$(printf '%q' "$BRANCH") R_PORT=$(printf '%q' "$PORT")"

    if [ "$RUN_LOCAL" = 1 ]; then
        info "mode lokal: $target_dir"
        env R_MODE="$mode" R_DIR="$target_dir" R_BRANCH="$BRANCH" R_PORT="$PORT" bash -c "$REMOTE_SCRIPT"
    else
        local ssh_cmd=(ssh)
        [ -n "$SSH_USER_ARG" ] && ssh_cmd+=(-l "$SSH_USER_ARG")
        ssh_cmd+=("$HOST" "$prelude bash -s")
        info "target: $HOST:$target_dir"
        "${ssh_cmd[@]}" <<<"$REMOTE_SCRIPT"
    fi
}

# ---------------------------------------------------------------------------
# 1. Cek kesehatan saja
# ---------------------------------------------------------------------------
if [ "$MODE" = "check" ]; then
    run_remote check "$REMOTE_DIR"
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. Push commit lokal (kalau ada dan bukan mode --local)
# ---------------------------------------------------------------------------
if [ "$RUN_LOCAL" = 0 ] && [ "$DO_PUSH" = 1 ] && git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain)" ]; then
        warn "ada perubahan belum di-commit di workstation — tidak ikut ter-deploy"
    fi
    if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        AHEAD=$(git rev-list --count '@{u}..HEAD')
        if [ "$AHEAD" -gt 0 ]; then
            info "push $AHEAD commit ke origin/$BRANCH"
            git push origin "$BRANCH"
        else
            dim "tidak ada commit lokal yang perlu di-push"
        fi
    else
        warn "branch lokal belum punya upstream — push dilewati"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Update server
# ---------------------------------------------------------------------------
run_remote deploy "$REMOTE_DIR"
info "selesai"
