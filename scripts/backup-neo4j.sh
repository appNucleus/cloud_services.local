#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ensure_runtime_env_file; load_runtime_env; require_service_enabled neo4j; configure_service_selection
retention="${DATA_BACKUP_RETENTION:-3}"; volume="${NEO4J_DATA_VOLUME_NAME:-db-neo4j-data}"; root="$(repo_path "${LOCAL_BACKUP_DIR:-./backups}")/neo4j"; mkdir -p "$root"; name="neo4j-volume-$(date +%Y%m%d-%H%M%S).tar.gz"
echo "Stopping Neo4j briefly to create a crash-consistent volume snapshot..."
compose stop neo4j
restart(){ compose up -d --wait neo4j >/dev/null 2>&1 || true; }
trap restart EXIT
docker run --rm -v "$volume:/source:ro" -v "$root:/backup" alpine:3.22 sh -c "cd /source && tar -czf /backup/$name ."
gzip -t "$root/$name"
compose up -d --wait neo4j
trap - EXIT
mapfile -t old < <(find "$root" -maxdepth 1 -type f -name 'neo4j-volume-*.tar.gz' -printf '%T@ %p\n' | sort -nr | tail -n "+$((retention + 1))" | cut -d' ' -f2-)
(( ${#old[@]} == 0 )) || rm -f -- "${old[@]}"
echo "Neo4j volume backup created: $root/$name (retaining newest $retention)"
