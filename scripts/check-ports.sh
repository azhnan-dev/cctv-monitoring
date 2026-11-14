#!/usr/bin/env bash
#
# check-ports.sh — cek port di server Coolify sebelum deploy.
#
#   ./scripts/check-ports.sh              # daftar semua port yang terpakai + pemiliknya
#   ./scripts/check-ports.sh 4025 4026    # cek port tertentu: TERPAKAI / BEBAS
#
# Sumber data (bukan tebakan):
#   1. API Coolify   → ports_mappings application + port dari compose service
#   2. Host (via SSH) → listener TCP (ss) + port yang dipublish Docker
#
# Env:
#   COOLIFY_URL   default http://10.111.111.3:8000
#   COOLIFY_TOKEN default isi ~/.coolify-token
#   COOLIFY_SSH   default root@10.111.111.3
#
set -euo pipefail

COOLIFY_URL="${COOLIFY_URL:-http://10.111.111.3:8000}"
COOLIFY_SSH="${COOLIFY_SSH:-root@10.111.111.3}"
TOKEN="${COOLIFY_TOKEN:-$(cat "${HOME}/.coolify-token" 2>/dev/null || true)}"

if [ -z "${TOKEN}" ]; then
    echo "xx token Coolify tidak ditemukan (set COOLIFY_TOKEN atau taruh di ~/.coolify-token)" >&2
    exit 1
fi

if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_DIM=""; C_OFF=""
fi

api() {
    curl -sS --max-time 10 -H "Authorization: Bearer ${TOKEN}" "${COOLIFY_URL}/api/v1/$1"
}

# ---------------------------------------------------------------- kumpulkan data
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# application: ports_mappings "4020:4000"
api applications | jq -r '.[] | select(.ports_mappings != null and .ports_mappings != "") | .name as $n | .ports_mappings | split(",")[] | "\(split(":")[0] | gsub("[^0-9]";""))\tapp: \($n)"' 2>/dev/null \
    | while IFS=$'\t' read -r port desc; do echo "${port}|${desc}"; done > "$tmpdir/apps.txt" || true

# service: decode docker_compose_raw, ambil baris ports "4023:3000"
api services | jq -r '.[].uuid' 2>/dev/null | while read -r uuid; do
    [ -n "$uuid" ] || continue
    name=$(api "services/${uuid}" | jq -r '.name // .uuid' 2>/dev/null)
    api "services/${uuid}" | jq -r '.docker_compose_raw // empty' 2>/dev/null \
        | base64 -d 2>/dev/null \
        | grep -Eo '"?[0-9]{2,5}:[0-9]{1,5}"?' \
        | cut -d: -f1 | tr -d '"' \
        | while read -r p; do echo "${p}|service: ${name}"; done
done > "$tmpdir/services.txt" 2>/dev/null || true

# host listener (ss) + docker publish
ssh -o BatchMode=yes -o ConnectTimeout=8 "$COOLIFY_SSH" 'ss -ltnH 2>/dev/null | awk "{print \$4}" | sed "s/.*://" | sort -u' 2>/dev/null \
    | grep -E '^[0-9]+$' | sed 's/$/|host listener/' > "$tmpdir/host.txt" || true

ssh -o BatchMode=yes -o ConnectTimeout=8 "$COOLIFY_SSH" 'docker ps --format "{{.Names}}|{{.Ports}}" 2>/dev/null' 2>/dev/null \
    | grep -E '\->' | while IFS='|' read -r cname ports; do
        echo "$ports" | tr ',' '\n' | grep -oE '[0-9]+->' | sed 's/->//' | while read -r p; do
            echo "${p}|docker: ${cname}"
        done
    done > "$tmpdir/docker.txt" || true

cat "$tmpdir"/*.txt 2>/dev/null | sort -n > "$tmpdir/all.txt" || true

# ---------------------------------------------------------------- mode: cek port
if [ $# -gt 0 ]; then
    status=0
    for port in "$@"; do
        [ -n "$port" ] || continue
        owners=$(awk -F'|' -v p="$port" '$1 == p { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }' "$tmpdir/all.txt" | sort -u | paste -sd', ' -)
        if [ -n "$owners" ]; then
            printf '%sTERPAKAI%s %-6s ← %s\n' "$C_RED" "$C_OFF" "$port" "$owners"
            status=1
        else
            printf '%sBEBAS%s    %-6s\n' "$C_GRN" "$C_OFF" "$port"
        fi
    done
    exit "$status"
fi

# ---------------------------------------------------------------- mode: inventory
printf '%sPort   Pemilik%s\n' "$C_DIM" "$C_OFF"
awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); if (!seen[$1 SUBSEP $2]++) { owner[$1] = owner[$1] ? owner[$1] ", " $2 : $2 } } END { for (p in owner) printf "%s|%s\n", p, owner[p] }' "$tmpdir/all.txt" \
    | sort -n | while IFS='|' read -r p o; do printf '%-6s %s\n' "$p" "$o"; done

echo
printf '%sCatatan:%s application/service = dari config Coolify; host listener / docker = kondisi nyata di server.\n' "$C_DIM" "$C_OFF"
printf '%sKonvensi port:%s 402x untuk service baru.\n' "$C_DIM" "$C_OFF"
