#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wait_for_health=false
if [[ "${1:-}" == "--wait" ]]; then
  wait_for_health=true
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--wait]" >&2
  exit 2
fi

ensure_runtime_env_file
load_runtime_env

bash "$repo_root/scripts/generate-pgadmin-config.sh"

mkdir -p \
  "$(repo_path "${POSTGRES_INITDB_DIR:-./initdb/postgres}")" \
  "$(repo_path "${DASHBOARD_WWW_DIR:-./www}")" \
  "$(repo_path "${LOCAL_BACKUP_DIR:-./backups}")"

cd "$repo_root"

log_tail="${DEPLOY_LOG_TAIL:-200}"

core_services=(
  postgres
  pgadmin
  redis
  redisinsight
  neo4j
  minio
  elasticmq
  elasticmq-ui
  dashboard
)

known_containers=(
  "${POSTGRES_CONTAINER_NAME:-db-postgres}"
  "${PGADMIN_CONTAINER_NAME:-db-pgadmin}"
  "${REDIS_CONTAINER_NAME:-db-redis}"
  "${REDISINSIGHT_CONTAINER_NAME:-db-redisinsight}"
  "${NEO4J_CONTAINER_NAME:-db-neo4j}"
  "${MINIO_CONTAINER_NAME:-db-minio}"
  "${ELASTICMQ_CONTAINER_NAME:-db-elasticmq}"
  "${ELASTICMQ_UI_CONTAINER_NAME:-db-elasticmq-ui}"
  "${DASHBOARD_CONTAINER_NAME:-db-dashboard}"
  "${MINIO_INIT_CONTAINER_NAME:-db-minio-init}"
)

print_deploy_debug() {
  local reason="${1:-unknown failure}"

  echo "::group::DB deployment debug: $reason"

  echo
  echo "===== Runtime context ====="
  echo "Repo root:        $repo_root"
  echo "Runtime env file: $runtime_env_file"
  echo "Wait enabled:     $wait_for_health"
  echo "Wait timeout:     ${COMPOSE_WAIT_TIMEOUT:-600}"
  echo "Log tail:         $log_tail"

  echo
  echo "===== Docker version ====="
  docker version || true

  echo
  echo "===== Docker Compose version ====="
  docker compose version || true

  echo
  echo "===== Compose services ====="
  compose config --services || true

  echo
  echo "===== Compose status ====="
  compose ps -a || true

  echo
  echo "===== DB containers ====="
  docker ps -a \
    --filter "name=db-" \
    --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" \
    || true

  echo
  echo "===== Container health/details ====="
  for container_name in "${known_containers[@]}"; do
    if docker container inspect "$container_name" >/dev/null 2>&1; then
      echo
      echo "----- $container_name inspect state -----"
      docker inspect "$container_name" \
        --format 'Name={{.Name}} Status={{.State.Status}} ExitCode={{.State.ExitCode}} Restarting={{.State.Restarting}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        || true

      echo
      echo "----- $container_name healthcheck history -----"
      docker inspect "$container_name" \
        --format '{{if .State.Health}}{{range .State.Health.Log}}Exit={{.ExitCode}} Start={{.Start}} End={{.End}} Output={{printf "%q" .Output}}{{println}}{{end}}{{else}}No Docker healthcheck configured.{{end}}' \
        || true

      echo
      echo "----- $container_name recent logs -----"
      docker logs "$container_name" --tail "$log_tail" 2>&1 || true
    else
      echo
      echo "----- $container_name -----"
      echo "Container does not exist."
    fi
  done

  echo "::endgroup::"
}

up_args=(
  up
  --detach
  --remove-orphans
)

if [[ "$wait_for_health" == "true" ]]; then
  up_args+=(--wait --wait-timeout "${COMPOSE_WAIT_TIMEOUT:-600}")
fi

echo "Starting long-running DB services only:"
printf ' - %s\n' "${core_services[@]}"

if ! compose "${up_args[@]}" "${core_services[@]}"; then
  print_deploy_debug "long-running service startup failed"
  exit 1
fi

# compose --wait already waits for every service with a Docker healthcheck.
# Do not add a blind sleep before smoke tests: healthy services are ready now,
# while services without healthchecks are exercised by verify.sh immediately
# after this script completes.
if [[ "$wait_for_health" == "true" ]]; then
  echo "Compose readiness checks passed; continuing without an arbitrary startup sleep."
fi

if [[ "${RUN_MINIO_INIT:-true}" == "true" ]]; then
  minio_init_container="${MINIO_INIT_CONTAINER_NAME:-db-minio-init}"

  echo
  echo "Running MinIO one-shot initialization separately..."

  compose rm --force --stop minio-init >/dev/null 2>&1 || true

  if ! compose up --detach --no-deps minio-init; then
    print_deploy_debug "failed to start minio-init"
    exit 1
  fi

  if ! docker container inspect "$minio_init_container" >/dev/null 2>&1; then
    print_deploy_debug "minio-init container was not created"
    exit 1
  fi

  minio_init_exit_code="$(docker wait "$minio_init_container" || echo 125)"

  echo
  echo "===== MinIO init logs ====="
  docker logs "$minio_init_container" --tail "$log_tail" 2>&1 || true

  if [[ "$minio_init_exit_code" != "0" ]]; then
    echo "MinIO initialization failed with exit code: $minio_init_exit_code" >&2
    print_deploy_debug "minio-init failed"
    exit "$minio_init_exit_code"
  fi

  compose rm --force --stop minio-init >/dev/null 2>&1 || true

  echo "MinIO one-shot initialization completed successfully."
else
  echo "RUN_MINIO_INIT is not true; skipping MinIO initialization."
fi

echo
echo "Started. Run: DEPLOY_ENV_FILE='$runtime_env_file' ./scripts/status.sh && DEPLOY_ENV_FILE='$runtime_env_file' ./scripts/verify.sh"