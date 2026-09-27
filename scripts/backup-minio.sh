#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ensure_runtime_env_file; load_runtime_env; require_service_enabled minio
retention="${DATA_BACKUP_RETENTION:-3}"; bucket="${MINIO_DEFAULT_BUCKET:-langgraph-app}"; root="$(repo_path "${LOCAL_BACKUP_DIR:-./backups}")/minio"; mkdir -p "$root"; dest="$root/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$dest"
docker run --rm --network "${DB_NETWORK_NAME:-db-local-net}" -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@minio:9000" -v "$dest:/backup" quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z mirror --overwrite "local/$bucket" /backup
test -n "$(find "$dest" -mindepth 1 -print -quit)" || echo "Warning: MinIO bucket is empty; backup snapshot is empty."
mapfile -t old < <(find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | tail -n "+$((retention + 1))" | cut -d' ' -f2-)
(( ${#old[@]} == 0 )) || rm -rf -- "${old[@]}"
echo "MinIO backup created: $dest (retaining newest $retention)"
