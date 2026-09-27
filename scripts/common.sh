#!/usr/bin/env bash
# Shared helpers for db.local scripts. Source this file from other scripts.

set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
runtime_env_file="${DEPLOY_ENV_FILE:-$repo_root/.env}"

ensure_runtime_env_file() {
  mkdir -p "$(dirname "$runtime_env_file")"

  if [[ ! -f "$runtime_env_file" ]]; then
    if [[ -f "$repo_root/.env.example" ]]; then
      install -m 600 "$repo_root/.env.example" "$runtime_env_file"
      echo "Created runtime environment file: $runtime_env_file"
    else
      echo "Missing .env.example; cannot create runtime environment file." >&2
      exit 1
    fi
  else
    chmod 600 "$runtime_env_file" 2>/dev/null || true
  fi
}

load_runtime_env() {
  if [[ -f "$runtime_env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$runtime_env_file"
    set +a
  fi
}

repo_path() {
  local path_value="$1"
  if [[ "$path_value" = /* ]]; then
    printf '%s' "$path_value"
  else
    printf '%s/%s' "$repo_root" "${path_value#./}"
  fi
}

service_enabled() {
  local service="$1"
  case "$service" in
    postgres) [[ "${ENABLE_POSTGRES:-true}" == "true" ]] ;;
    redis) [[ "${ENABLE_REDIS:-true}" == "true" ]] ;;
    neo4j) [[ "${ENABLE_NEO4J:-true}" == "true" ]] ;;
    minio) [[ "${ENABLE_MINIO:-true}" == "true" ]] ;;
    elasticmq) [[ "${ENABLE_ELASTICMQ:-true}" == "true" ]] ;;
    cognito) [[ "${ENABLE_COGNITO:-true}" == "true" ]] ;;
    *) echo "Unknown logical service: $service" >&2; return 2 ;;
  esac
}

require_service_enabled() {
  local service="$1"
  if ! service_enabled "$service"; then
    echo "Service '$service' is disabled in $runtime_env_file; operation skipped." >&2
    exit 3
  fi
}

configure_service_selection() {
  enabled_profiles=()
  enabled_services=(ui-gateway dashboard)
  disabled_services=()
  disabled_containers=()

  if service_enabled postgres; then
    enabled_profiles+=(postgres)
    enabled_services+=(postgres pgadmin)
  else
    disabled_services+=(postgres pgadmin)
    disabled_containers+=("${POSTGRES_CONTAINER_NAME:-db-postgres}" "${PGADMIN_CONTAINER_NAME:-db-pgadmin}")
  fi

  if service_enabled redis; then
    enabled_profiles+=(redis)
    enabled_services+=(redis redisinsight)
  else
    disabled_services+=(redis redisinsight)
    disabled_containers+=("${REDIS_CONTAINER_NAME:-db-redis}" "${REDISINSIGHT_CONTAINER_NAME:-db-redisinsight}")
  fi

  if service_enabled neo4j; then
    enabled_profiles+=(neo4j)
    enabled_services+=(neo4j)
  else
    disabled_services+=(neo4j)
    disabled_containers+=("${NEO4J_CONTAINER_NAME:-db-neo4j}")
  fi

  if service_enabled minio; then
    enabled_profiles+=(minio)
    enabled_services+=(minio)
  else
    disabled_services+=(minio minio-init)
    disabled_containers+=("${MINIO_CONTAINER_NAME:-db-minio}" "${MINIO_INIT_CONTAINER_NAME:-db-minio-init}")
  fi

  if service_enabled elasticmq; then
    enabled_profiles+=(elasticmq)
    enabled_services+=(elasticmq elasticmq-ui)
  else
    disabled_services+=(elasticmq elasticmq-ui)
    disabled_containers+=("${ELASTICMQ_CONTAINER_NAME:-db-elasticmq}" "${ELASTICMQ_UI_CONTAINER_NAME:-db-elasticmq-ui}")
  fi

  if service_enabled cognito; then
    enabled_profiles+=(cognito)
    enabled_services+=(cognito)
  else
    disabled_services+=(cognito)
    disabled_containers+=("${COGNITO_CONTAINER_NAME:-db-cognito}")
  fi

  local joined=""
  if (( ${#enabled_profiles[@]} > 0 )); then
    local IFS=,
    joined="${enabled_profiles[*]}"
  fi
  export COMPOSE_PROFILES="$joined"
}

compose() {
  docker compose --env-file "$runtime_env_file" "$@"
}

compose_all_profiles() {
  docker compose --env-file "$runtime_env_file" --profile '*' "$@"
}
