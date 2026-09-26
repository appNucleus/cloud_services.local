#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ensure_runtime_env_file; load_runtime_env
retention="${DATA_BACKUP_RETENTION:-3}"
container="${NEO4J_CONTAINER_NAME:-db-neo4j}"
root="$(repo_path "${LOCAL_BACKUP_DIR:-./backups}")/neo4j"; mkdir -p "$root"
name="neo4j-$(date +%Y%m%d-%H%M%S).dump"
echo "Neo4j Community dump requires a brief database stop. Persistent Docker volumes are not removed."
docker exec "$container" neo4j stop
trap 'docker exec "$container" neo4j start >/dev/null 2>&1 || true' EXIT
docker exec "$container" neo4j-admin database dump neo4j --to-path=/backups 2>/dev/null || {
  echo "Neo4j Community image does not expose a writable /backups mount; use the documented offline volume-copy procedure." >&2
  exit 1
}
docker cp "$container:/backups/neo4j.dump" "$root/$name"
docker exec "$container" rm -f /backups/neo4j.dump || true
docker exec "$container" neo4j start
trap - EXIT
test -s "$root/$name"
mapfile -t old < <(find "$root" -maxdepth 1 -type f -name 'neo4j-*.dump' -printf '%T@ %p\n' | sort -nr | tail -n "+$((retention + 1))" | cut -d' ' -f2-)
(( ${#old[@]} == 0 )) || rm -f -- "${old[@]}"
echo "Neo4j backup created: $root/$name"
