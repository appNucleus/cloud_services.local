#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ensure_runtime_env_file; load_runtime_env; require_service_enabled postgres
container="${POSTGRES_CONTAINER_NAME:-db-postgres}"; user="${POSTGRES_USER:-langgraph_user}"; dir="$(repo_path "${POSTGRES_BACKUP_DIR:-./backups/postgres}")"
backup="${1:-$(find "$dir" -maxdepth 1 -type f -name '*.sql.gz' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)}"
[[ -n "$backup" && -f "$backup" ]] || { echo "No PostgreSQL backup found." >&2; exit 1; }
gzip -t "$backup"; db="db_restore_test_$$"
cleanup(){ docker exec "$container" dropdb -U "$user" --if-exists "$db" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker exec "$container" createdb -U "$user" "$db"
gzip -dc "$backup" | docker exec -i "$container" psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" >/dev/null
docker exec "$container" psql -U "$user" -d "$db" -tAc 'SELECT 1;' | grep -qx 1
echo "Restore validation passed: $backup"
