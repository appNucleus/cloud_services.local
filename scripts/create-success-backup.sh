#!/usr/bin/env bash
set -Eeuo pipefail

: "${DEPLOY_ENV_FILE:?DEPLOY_ENV_FILE is required}"
if [[ -f "$DEPLOY_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV_FILE"
  set +a
fi
: "${BACKUP_ROOT:?BACKUP_ROOT is required}"
: "${ROLLBACK_STATE_DIR:?ROLLBACK_STATE_DIR is required}"

umask 077
mkdir -p "$BACKUP_ROOT" "$ROLLBACK_STATE_DIR"
timestamp="$(date +'%Y%m%d-%H%M%S')"
final_backup="$BACKUP_ROOT/$timestamp"
staging_backup="$BACKUP_ROOT/.staging-${timestamp}-${GITHUB_RUN_ID:-manual}-$$"
cleanup_staging(){ rm -rf -- "$staging_backup"; }
trap cleanup_staging EXIT
[[ ! -e "$final_backup" ]] || { echo "Backup destination already exists: $final_backup" >&2; exit 1; }
mkdir -p "$staging_backup/source"

git archive --format=tar HEAD | tar -xf - -C "$staging_backup/source"
install -m 600 "$DEPLOY_ENV_FILE" "$staging_backup/runtime.env"
printf '%s\n' "managed-db-success-backup-v1" > "$staging_backup/.db-success-backup"
printf '%s\n' "${GITHUB_SHA:-$(git rev-parse HEAD)}" > "$staging_backup/deployed-commit.txt"
date --iso-8601=seconds > "$staging_backup/deployed-at.txt"
printf '%s\n' "${GITHUB_RUN_ID:-manual}" > "$staging_backup/github-run-id.txt"
printf '%s\n' "${GITHUB_RUN_ATTEMPT:-1}" > "$staging_backup/github-run-attempt.txt"
printf '%s\n' "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-local/manual}/actions/runs/${GITHUB_RUN_ID:-manual}" > "$staging_backup/github-run-url.txt"

docker compose --env-file "$DEPLOY_ENV_FILE" --profile '*' config > "$staging_backup/compose-resolved.yaml"
docker compose --env-file "$DEPLOY_ENV_FILE" --profile '*' ps --all > "$staging_backup/docker-compose-ps.txt"
docker compose --env-file "$DEPLOY_ENV_FILE" --profile '*' logs --no-color --tail=200 > "$staging_backup/docker-compose-logs.txt" 2>&1 || true
docker compose --env-file "$DEPLOY_ENV_FILE" --profile '*' ps --all --format json > "$staging_backup/docker-compose-ps.json" 2>/dev/null || true

container_names=(
  "${POSTGRES_CONTAINER_NAME:-db-postgres}"
  "${PGADMIN_CONTAINER_NAME:-db-pgadmin}"
  "${REDIS_CONTAINER_NAME:-db-redis}"
  "${REDISINSIGHT_CONTAINER_NAME:-db-redisinsight}"
  "${NEO4J_CONTAINER_NAME:-db-neo4j}"
  "${MINIO_CONTAINER_NAME:-db-minio}"
  "${ELASTICMQ_CONTAINER_NAME:-db-elasticmq}"
  "${ELASTICMQ_UI_CONTAINER_NAME:-db-elasticmq-ui}"
  "${COGNITO_CONTAINER_NAME:-db-cognito}"
  "${UI_GATEWAY_CONTAINER_NAME:-db-ui-gateway}"
  "${DASHBOARD_CONTAINER_NAME:-db-dashboard}"
)
mkdir -p "$staging_backup/container-inspect"
for container_name in "${container_names[@]}"; do
  docker container inspect "$container_name" > "$staging_backup/container-inspect/${container_name}.json" 2>/dev/null || true
done

(
  cd "$staging_backup"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

mv -- "$staging_backup" "$final_backup"
trap - EXIT
printf '%s\n' "$final_backup" > "$ROLLBACK_STATE_DIR/new-backup-path.txt"
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d ! -path "$final_backup" -exec rm -rf -- {} +
if [[ -n "${GITHUB_ENV:-}" ]]; then echo "CURRENT_BACKUP=$final_backup" >> "$GITHUB_ENV"; fi
echo "Created successful DB deployment backup: $final_backup"
echo "Only the current successful deployment backup is retained. Docker volumes were not touched."
