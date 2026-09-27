#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ensure_runtime_env_file; load_runtime_env; require_service_enabled redis
container="${REDIS_CONTAINER_NAME:-db-redis}"; password="${REDIS_PASSWORD:?REDIS_PASSWORD is required}"; retention="${DATA_BACKUP_RETENTION:-3}"
dir="$(repo_path "${LOCAL_BACKUP_DIR:-./backups}")/redis"; mkdir -p "$dir"; out="$dir/redis-$(date +%Y%m%d-%H%M%S).rdb"
docker exec "$container" redis-cli -a "$password" --rdb /tmp/db-local-backup.rdb >/dev/null
docker cp "$container:/tmp/db-local-backup.rdb" "$out"; docker exec "$container" rm -f /tmp/db-local-backup.rdb; test -s "$out"
mapfile -t old < <(find "$dir" -maxdepth 1 -type f -name 'redis-*.rdb' -printf '%T@ %p\n' | sort -nr | tail -n "+$((retention + 1))" | cut -d' ' -f2-)
(( ${#old[@]} == 0 )) || rm -f -- "${old[@]}"
echo "Redis backup created: $out (retaining newest $retention)"
