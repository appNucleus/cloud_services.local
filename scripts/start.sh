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
configure_service_selection

bash "$repo_root/scripts/generate-dashboard-state.sh"
if service_enabled postgres; then
  bash "$repo_root/scripts/generate-pgadmin-config.sh"
fi
if service_enabled cognito; then
  bash "$repo_root/scripts/generate-cognito-config.sh"
fi

mkdir -p \
  "$(repo_path "${POSTGRES_INITDB_DIR:-./initdb/postgres}")" \
  "$(repo_path "${DASHBOARD_WWW_DIR:-./www}")" \
  "$(repo_path "${LOCAL_BACKUP_DIR:-./backups}")"

cd "$repo_root"
log_tail="${DEPLOY_LOG_TAIL:-200}"

known_containers=(
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
  "${MINIO_INIT_CONTAINER_NAME:-db-minio-init}"
)

print_deploy_debug() {
  local reason="${1:-unknown failure}"
  echo "::group::DB deployment debug: $reason"
  echo
  echo "===== Runtime context ====="
  echo "Repo root:        $repo_root"
  echo "Runtime env file: $runtime_env_file"
  echo "Platform host:    ${PLATFORM_HOSTNAME:-aws.home.arpa}"
  echo "Profiles:         ${COMPOSE_PROFILES:-<none>}"
  echo "Wait enabled:     $wait_for_health"
  echo "Wait timeout:     ${COMPOSE_WAIT_TIMEOUT:-600}"
  echo "Log tail:         $log_tail"
  echo
  docker version || true
  docker compose version || true
  echo
  echo "===== Compose services (all profiles) ====="
  compose_all_profiles config --services || true
  echo
  echo "===== Compose status (all profiles) ====="
  compose_all_profiles ps -a || true
  echo
  echo "===== DB containers ====="
  docker ps -a --filter "name=db-" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" || true

  for container_name in "${known_containers[@]}"; do
    if docker container inspect "$container_name" >/dev/null 2>&1; then
      echo
      echo "----- $container_name -----"
      docker inspect "$container_name" \
        --format 'Name={{.Name}} Status={{.State.Status}} ExitCode={{.State.ExitCode}} Restarting={{.State.Restarting}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' || true
      docker logs "$container_name" --tail "$log_tail" 2>&1 || true
    fi
  done
  echo "::endgroup::"
}

# Reconcile enabled -> disabled transitions explicitly. Compose profiles do not
# guarantee removal of containers that belonged to a profile active previously.
if (( ${#disabled_containers[@]} > 0 )); then
  echo "Reconciling disabled service containers (volumes are preserved):"
  for container_name in "${disabled_containers[@]}"; do
    if docker container inspect "$container_name" >/dev/null 2>&1; then
      echo " - removing $container_name"
      docker rm --force "$container_name" >/dev/null
    else
      echo " - $container_name already absent"
    fi
  done
fi

# Cognito Local uses an intentionally external named volume so existing user-pool
# data survives service toggles and migrations without Compose ownership warnings.
# Cognito writes its config file at runtime, so seed the generated config into the
# writable persistent volume before startup instead of bind-mounting it read-only.
if service_enabled cognito; then
  cognito_image="${COGNITO_IMAGE:-jagregory/cognito-local:5.3.0}"
  cognito_volume="${COGNITO_VOLUME_NAME:-db-cognito-data}"
  cognito_config="$(repo_path "${COGNITO_CONFIG_FILE:-./generated/cognito/config.json}")"

  if docker volume inspect "$cognito_volume" >/dev/null 2>&1; then
    echo "Using Cognito Local persistent volume: $cognito_volume"
  else
    docker volume create "$cognito_volume" >/dev/null
    echo "Created Cognito Local persistent volume: $cognito_volume"
  fi

  if ! docker image inspect "$cognito_image" >/dev/null 2>&1; then
    docker pull "$cognito_image"
  fi
  docker run --rm \
    --entrypoint /bin/sh \
    --mount "type=volume,src=$cognito_volume,dst=/app/.cognito" \
    --mount "type=bind,src=$cognito_config,dst=/tmp/config.json,readonly" \
    "$cognito_image" \
    -c 'cp /tmp/config.json /app/.cognito/config.json && chmod 0644 /app/.cognito/config.json'
  echo "Cognito Local configuration synchronized into persistent volume: $cognito_volume"
fi

up_args=(up --detach --remove-orphans)
if [[ "$wait_for_health" == "true" ]]; then
  up_args+=(--wait --wait-timeout "${COMPOSE_WAIT_TIMEOUT:-600}")
fi

echo "Starting enabled long-running services:"
printf ' - %s\n' "${enabled_services[@]}"

if ! compose "${up_args[@]}" "${enabled_services[@]}"; then
  print_deploy_debug "long-running service startup failed"
  exit 1
fi

if [[ "$wait_for_health" == "true" ]]; then
  echo "Compose health checks passed; host-level smoke tests will retry remaining endpoints until ready."
fi

if service_enabled minio && [[ "${RUN_MINIO_INIT:-true}" == "true" ]]; then
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
elif ! service_enabled minio; then
  echo "MinIO is disabled; skipping MinIO initialization."
else
  echo "RUN_MINIO_INIT is false; skipping MinIO initialization."
fi

echo
echo "Started. Run: DEPLOY_ENV_FILE='$runtime_env_file' ./scripts/status.sh && DEPLOY_ENV_FILE='$runtime_env_file' ./scripts/verify.sh"
