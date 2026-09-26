#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_runtime_env_file
load_runtime_env

POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-db-postgres}"
POSTGRES_DB="${POSTGRES_DB:-langgraph_app}"
POSTGRES_USER="${POSTGRES_USER:-langgraph_user}"
POSTGRES_BACKUP_DIR="${POSTGRES_BACKUP_DIR:-./backups/postgres}"
POSTGRES_BACKUP_RETENTION="${POSTGRES_BACKUP_RETENTION:-7}"

backup_dir="$(repo_path "$POSTGRES_BACKUP_DIR")"
mkdir -p "$backup_dir"
ts="$(date +%Y%m%d-%H%M%S)"
out="$backup_dir/${POSTGRES_DB}-${ts}.sql.gz"

docker exec "$POSTGRES_CONTAINER_NAME" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip > "$out"
gzip -t "$out"

mapfile -t old_backups < <(find "$backup_dir" -maxdepth 1 -type f -name "${POSTGRES_DB}-*.sql.gz" -printf "%T@ %p\n" | sort -nr | tail -n "+$((POSTGRES_BACKUP_RETENTION + 1))" | cut -d" " -f2-)
if (( ${#old_backups[@]} > 0 )); then
  rm -f -- "${old_backups[@]}"
fi

ls -lh "$out"
echo "PostgreSQL backup verified; retaining newest $POSTGRES_BACKUP_RETENTION backups."
