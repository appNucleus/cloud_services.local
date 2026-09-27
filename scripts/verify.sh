#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_runtime_env_file
load_runtime_env
configure_service_selection

POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-db-postgres}"
PGADMIN_CONTAINER_NAME="${PGADMIN_CONTAINER_NAME:-db-pgadmin}"
REDIS_CONTAINER_NAME="${REDIS_CONTAINER_NAME:-db-redis}"
REDISINSIGHT_CONTAINER_NAME="${REDISINSIGHT_CONTAINER_NAME:-db-redisinsight}"
NEO4J_CONTAINER_NAME="${NEO4J_CONTAINER_NAME:-db-neo4j}"
MINIO_CONTAINER_NAME="${MINIO_CONTAINER_NAME:-db-minio}"
ELASTICMQ_CONTAINER_NAME="${ELASTICMQ_CONTAINER_NAME:-db-elasticmq}"
ELASTICMQ_UI_CONTAINER_NAME="${ELASTICMQ_UI_CONTAINER_NAME:-db-elasticmq-ui}"
COGNITO_CONTAINER_NAME="${COGNITO_CONTAINER_NAME:-db-cognito}"
MINIO_INIT_CONTAINER_NAME="${MINIO_INIT_CONTAINER_NAME:-db-minio-init}"
PLATFORM_HOSTNAME="${PLATFORM_HOSTNAME:-aws.home.arpa}"

ELASTICMQ_PORT="${ELASTICMQ_PORT:-9324}"
ELASTICMQ_UI_PORT="${ELASTICMQ_UI_PORT:-9325}"
PGADMIN_PORT="${PGADMIN_PORT:-5050}"
REDISINSIGHT_PORT="${REDISINSIGHT_PORT:-5540}"
NEO4J_HTTP_PORT="${NEO4J_HTTP_PORT:-7474}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
COGNITO_PORT="${COGNITO_PORT:-9229}"
COGNITO_UI_PORT="${COGNITO_UI_PORT:-9230}"
POSTGRES_USER="${POSTGRES_USER:-langgraph_user}"
POSTGRES_DB="${POSTGRES_DB:-langgraph_app}"
REDIS_PASSWORD="${REDIS_PASSWORD:-change_me_redis_2026}"
NEO4J_USERNAME="${NEO4J_USERNAME:-neo4j}"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-change_me_neo4j_2026}"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-change_me_minio_2026}"
MINIO_DEFAULT_BUCKET="${MINIO_DEFAULT_BUCKET:-langgraph-app}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8003}"
DASHBOARD_HOST_BIND="${DASHBOARD_HOST_BIND:-127.0.0.1}"
SMOKE_READY_TIMEOUT="${SMOKE_READY_TIMEOUT:-90}"

retry_http() {
  local name="$1" url="$2"
  shift 2
  local deadline=$((SECONDS + SMOKE_READY_TIMEOUT))
  while (( SECONDS < deadline )); do
    if curl -fsS --connect-timeout 2 --max-time 5 "$@" "$url" >/dev/null 2>&1; then
      echo "$name: ok"
      return 0
    fi
    sleep 2
  done
  echo "$name did not become ready within ${SMOKE_READY_TIMEOUT}s: $url" >&2
  return 1
}

retry_elasticmq() {
  local response deadline=$((SECONDS + SMOKE_READY_TIMEOUT))
  while (( SECONDS < deadline )); do
    if response="$(curl -fsS --connect-timeout 2 --max-time 5 -X POST \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data 'Action=ListQueues&Version=2012-11-05' \
      "http://127.0.0.1:${ELASTICMQ_PORT}/" 2>/dev/null)" \
      && [[ "$response" == *"ListQueuesResponse"* ]]; then
      echo "ElasticMQ SQS API: ok"
      return 0
    fi
    sleep 2
  done
  echo "ElasticMQ SQS API did not become ready within ${SMOKE_READY_TIMEOUT}s." >&2
  return 1
}

retry_cognito() {
  local response deadline=$((SECONDS + SMOKE_READY_TIMEOUT))
  while (( SECONDS < deadline )); do
    if response="$(curl -fsS --connect-timeout 2 --max-time 5 -X POST \
      -H 'Content-Type: application/x-amz-json-1.1' \
      -H 'X-Amz-Target: AWSCognitoIdentityProviderService.ListUserPools' \
      --data '{"MaxResults":1}' \
      "http://127.0.0.1:${COGNITO_PORT}/" 2>/dev/null)" \
      && [[ "$response" == *'"UserPools"'* ]]; then
      echo "Cognito Local User Pools API: ok"
      return 0
    fi
    sleep 2
  done
  echo "Cognito Local API did not become ready within ${SMOKE_READY_TIMEOUT}s." >&2
  return 1
}

assert_service_running() {
  local service="$1"
  mapfile -t service_ids < <(compose ps -q "$service" | sed '/^[[:space:]]*$/d')
  if (( ${#service_ids[@]} != 1 )); then
    echo "Expected exactly one container for enabled service '$service'; found ${#service_ids[@]}." >&2
    exit 1
  fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "${service_ids[0]}")" != "true" ]]; then
    echo "Container for enabled service '$service' is not running." >&2
    exit 1
  fi
}

assert_container_absent() {
  local container_name="$1"
  if docker container inspect "$container_name" >/dev/null 2>&1; then
    echo "Disabled service container still exists: $container_name" >&2
    exit 1
  fi
}

verify_disabled_group() {
  local label="$1"; shift
  for container_name in "$@"; do
    assert_container_absent "$container_name"
  done
  echo "$label: disabled (containers absent, volumes preserved)"
}

cd "$repo_root"
printf '\n===== Containers =====\n'
compose_all_profiles ps -a

assert_service_running ui-gateway
assert_service_running dashboard

if service_enabled postgres; then
  assert_service_running postgres
  assert_service_running pgadmin
else
  verify_disabled_group "PostgreSQL" "$POSTGRES_CONTAINER_NAME" "$PGADMIN_CONTAINER_NAME"
fi

if service_enabled redis; then
  assert_service_running redis
  assert_service_running redisinsight
else
  verify_disabled_group "Redis" "$REDIS_CONTAINER_NAME" "$REDISINSIGHT_CONTAINER_NAME"
fi

if service_enabled neo4j; then
  assert_service_running neo4j
else
  verify_disabled_group "Neo4j" "$NEO4J_CONTAINER_NAME"
fi

if service_enabled minio; then
  assert_service_running minio
else
  verify_disabled_group "MinIO" "$MINIO_CONTAINER_NAME" "$MINIO_INIT_CONTAINER_NAME"
fi

if service_enabled elasticmq; then
  assert_service_running elasticmq
  assert_service_running elasticmq-ui
else
  verify_disabled_group "ElasticMQ" "$ELASTICMQ_CONTAINER_NAME" "$ELASTICMQ_UI_CONTAINER_NAME"
fi

if service_enabled cognito; then
  assert_service_running cognito
else
  verify_disabled_group "Cognito Local" "$COGNITO_CONTAINER_NAME"
fi

# The MinIO initializer is always one-shot and must not remain after startup.
assert_container_absent "$MINIO_INIT_CONTAINER_NAME"
echo "Container cardinality/state checks: ok"

printf '\n===== Dashboard =====\n'
retry_http "dashboard" "http://${DASHBOARD_HOST_BIND}:${DASHBOARD_PORT}/index.html"
runtime_state="$(curl -fsS --connect-timeout 2 --max-time 5 "http://${DASHBOARD_HOST_BIND}:${DASHBOARD_PORT}/runtime-config.js")"
[[ "$runtime_state" == *"hostname: \"${PLATFORM_HOSTNAME}\""* ]] || { echo "Dashboard runtime hostname is not synchronized." >&2; exit 1; }
for service in postgres redis neo4j minio elasticmq cognito; do
  expected=false
  service_enabled "$service" && expected=true
  [[ "$runtime_state" == *"${service}: ${expected}"* ]] || { echo "Dashboard runtime state mismatch for $service." >&2; exit 1; }
done
echo "Dashboard configured-state metadata: ok"

verify_host_caddy="${VERIFY_HOST_CADDY:-auto}"
should_verify_host_caddy=false
case "$verify_host_caddy" in
  true) should_verify_host_caddy=true ;;
  false) should_verify_host_caddy=false ;;
  auto)
    [[ -r /etc/caddy/Caddyfile ]] && should_verify_host_caddy=true
    ;;
esac

if [[ "$should_verify_host_caddy" == "true" ]]; then
  printf '\n===== Host Caddy dashboard route =====\n'
  if [[ -r /etc/caddy/Caddyfile ]]; then
    grep -Fq "${PLATFORM_HOSTNAME} {" /etc/caddy/Caddyfile || {
      echo "Host Caddyfile does not contain the expected ${PLATFORM_HOSTNAME} site block." >&2
      exit 1
    }
  fi
  retry_http "dashboard through host Caddy" "https://${PLATFORM_HOSTNAME}/index.html" \
    --insecure --resolve "${PLATFORM_HOSTNAME}:443:127.0.0.1"
  host_runtime_state="$(curl -kfsS --connect-timeout 2 --max-time 5 \
    --resolve "${PLATFORM_HOSTNAME}:443:127.0.0.1" \
    "https://${PLATFORM_HOSTNAME}/runtime-config.js")"
  [[ "$host_runtime_state" == *"hostname: \"${PLATFORM_HOSTNAME}\""* ]] || {
    echo "Host-Caddy dashboard runtime hostname is not synchronized." >&2
    exit 1
  }
  echo "Host Caddy dashboard route: ok (${PLATFORM_HOSTNAME})"
else
  echo "Host Caddy dashboard verification skipped (VERIFY_HOST_CADDY=${verify_host_caddy})."
fi

if service_enabled postgres; then
  printf '\n===== pgAdmin =====\n'
  retry_http "pgAdmin HTTPS gateway" "https://${PLATFORM_HOSTNAME}:${PGADMIN_PORT}/misc/ping" --insecure --resolve "${PLATFORM_HOSTNAME}:${PGADMIN_PORT}:127.0.0.1"
  printf '\n===== PostgreSQL =====\n'
  docker exec "$POSTGRES_CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
  docker exec "$POSTGRES_CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "CREATE EXTENSION IF NOT EXISTS vector; SELECT extname FROM pg_extension WHERE extname='vector';"
fi

if service_enabled redis; then
  printf '\n===== Redis =====\n'
  docker exec "$REDIS_CONTAINER_NAME" redis-cli -a "$REDIS_PASSWORD" ping
  printf '\n===== RedisInsight =====\n'
  retry_http "RedisInsight HTTPS gateway" "https://${PLATFORM_HOSTNAME}:${REDISINSIGHT_PORT}/" --insecure --resolve "${PLATFORM_HOSTNAME}:${REDISINSIGHT_PORT}:127.0.0.1"
fi

if service_enabled neo4j; then
  printf '\n===== Neo4j =====\n'
  docker exec "$NEO4J_CONTAINER_NAME" cypher-shell -u "$NEO4J_USERNAME" -p "$NEO4J_PASSWORD" "RETURN 1 AS ok;"
  retry_http "Neo4j Browser HTTPS gateway" "https://${PLATFORM_HOSTNAME}:${NEO4J_HTTP_PORT}/" --insecure --resolve "${PLATFORM_HOSTNAME}:${NEO4J_HTTP_PORT}:127.0.0.1"
fi

if service_enabled minio; then
  printf '\n===== MinIO =====\n'
  docker exec "$MINIO_CONTAINER_NAME" mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
  if ! docker exec "$MINIO_CONTAINER_NAME" mc stat "local/$MINIO_DEFAULT_BUCKET" >/dev/null 2>&1; then
    echo "Required MinIO bucket is missing: $MINIO_DEFAULT_BUCKET" >&2
    exit 1
  fi
  echo "MinIO bucket $MINIO_DEFAULT_BUCKET: ok"
  retry_http "MinIO console HTTPS gateway" "https://${PLATFORM_HOSTNAME}:${MINIO_CONSOLE_PORT}/" --insecure --resolve "${PLATFORM_HOSTNAME}:${MINIO_CONSOLE_PORT}:127.0.0.1"
fi

if service_enabled elasticmq; then
  printf '\n===== ElasticMQ =====\n'
  retry_elasticmq
  printf '\n===== ElasticMQ UI =====\n'
  retry_http "ElasticMQ UI HTTPS gateway" "https://${PLATFORM_HOSTNAME}:${ELASTICMQ_UI_PORT}/" --insecure --resolve "${PLATFORM_HOSTNAME}:${ELASTICMQ_UI_PORT}:127.0.0.1"
fi

if service_enabled cognito; then
  printf '\n===== Cognito Local =====\n'
  retry_http "Cognito Local HTTPS UI" "https://${PLATFORM_HOSTNAME}:${COGNITO_UI_PORT}/" --insecure --resolve "${PLATFORM_HOSTNAME}:${COGNITO_UI_PORT}:127.0.0.1"
  cognito_ui="$(curl -fsS --insecure --resolve "${PLATFORM_HOSTNAME}:${COGNITO_UI_PORT}:127.0.0.1" "https://${PLATFORM_HOSTNAME}:${COGNITO_UI_PORT}/")"
  [[ "$cognito_ui" == *"Cognito Local"* && "$cognito_ui" == *"User Pools"* ]] || {
    echo "Cognito Local HTTPS landing UI did not return the expected page." >&2
    exit 1
  }
  echo "Cognito Local HTTPS landing UI: ok"
  retry_cognito
  issuer="http://${PLATFORM_HOSTNAME}:${COGNITO_PORT}"
  docker exec "$COGNITO_CONTAINER_NAME" cat /app/.cognito/config.json | grep -Fq "\"IssuerDomain\": \"$issuer\"" || {
    echo "Cognito Local issuer is not synchronized with PLATFORM_HOSTNAME: $issuer" >&2
    exit 1
  }
  echo "Cognito Local issuer: ok ($issuer)"
fi

printf '\nAll checks completed.\n'
