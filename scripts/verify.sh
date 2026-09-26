#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

load_runtime_env

POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-db-postgres}"
REDIS_CONTAINER_NAME="${REDIS_CONTAINER_NAME:-db-redis}"
NEO4J_CONTAINER_NAME="${NEO4J_CONTAINER_NAME:-db-neo4j}"
MINIO_CONTAINER_NAME="${MINIO_CONTAINER_NAME:-db-minio}"
ELASTICMQ_PORT="${ELASTICMQ_PORT:-9324}"
ELASTICMQ_UI_PORT="${ELASTICMQ_UI_PORT:-9325}"
PGADMIN_PORT="${PGADMIN_PORT:-5050}"
REDISINSIGHT_PORT="${REDISINSIGHT_PORT:-5540}"
NEO4J_HTTP_PORT="${NEO4J_HTTP_PORT:-7474}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
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
  local response
  local deadline=$((SECONDS + SMOKE_READY_TIMEOUT))

  while (( SECONDS < deadline )); do
    if response="$(curl -fsS --connect-timeout 2 --max-time 5 -X POST \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data 'Action=ListQueues&Version=2012-11-05' \
      "http://127.0.0.1:${ELASTICMQ_PORT}/" 2>/dev/null)" \
      && [[ "$response" == *"ListQueuesResponse"* ]]; then
      echo "elasticmq SQS API: ok"
      return 0
    fi
    sleep 2
  done

  echo "ElasticMQ SQS API did not become ready within ${SMOKE_READY_TIMEOUT}s." >&2
  return 1
}

cd "$repo_root"

printf '\n===== Containers =====\n'
compose ps

# Exactly one Compose container must exist for each long-running service.
# Fixed container_name values already prevent same-name duplicates; this also
# catches accidental scaling/project drift before endpoint tests run.
for service in postgres pgadmin redis redisinsight neo4j minio elasticmq elasticmq-ui ui-gateway dashboard; do
  mapfile -t service_ids < <(compose ps -q "$service" | sed '/^[[:space:]]*$/d')
  if (( ${#service_ids[@]} != 1 )); then
    echo "Expected exactly one container for service '$service'; found ${#service_ids[@]}." >&2
    exit 1
  fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "${service_ids[0]}")" != "true" ]]; then
    echo "Container for service '$service' is not running." >&2
    exit 1
  fi
done
echo "Compose cardinality: exactly one running container per service."

printf '\n===== Dashboard =====\n'
retry_http "dashboard" "http://${DASHBOARD_HOST_BIND}:${DASHBOARD_PORT}/index.html"

printf '\n===== pgAdmin =====\n'
retry_http "pgAdmin HTTPS gateway" "https://dbs.home.arpa:${PGADMIN_PORT}/misc/ping" --insecure --resolve "dbs.home.arpa:${PGADMIN_PORT}:127.0.0.1"

printf '\n===== PostgreSQL =====\n'
docker exec "$POSTGRES_CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
docker exec "$POSTGRES_CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "CREATE EXTENSION IF NOT EXISTS vector; SELECT extname FROM pg_extension WHERE extname='vector';"

printf '\n===== Redis =====\n'
docker exec "$REDIS_CONTAINER_NAME" redis-cli -a "$REDIS_PASSWORD" ping

printf '\n===== RedisInsight =====\n'
retry_http "RedisInsight HTTPS gateway" "https://dbs.home.arpa:${REDISINSIGHT_PORT}/" --insecure --resolve "dbs.home.arpa:${REDISINSIGHT_PORT}:127.0.0.1"

printf '\n===== Neo4j =====\n'
docker exec "$NEO4J_CONTAINER_NAME" cypher-shell -u "$NEO4J_USERNAME" -p "$NEO4J_PASSWORD" "RETURN 1 AS ok;"
retry_http "Neo4j Browser HTTPS gateway" "https://dbs.home.arpa:${NEO4J_HTTP_PORT}/" --insecure --resolve "dbs.home.arpa:${NEO4J_HTTP_PORT}:127.0.0.1"

printf '\n===== MinIO =====\n'
docker exec "$MINIO_CONTAINER_NAME" mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
if ! docker exec "$MINIO_CONTAINER_NAME" mc stat "local/$MINIO_DEFAULT_BUCKET" >/dev/null 2>&1; then
  echo "Required MinIO bucket is missing: $MINIO_DEFAULT_BUCKET" >&2
  exit 1
fi
echo "MinIO bucket $MINIO_DEFAULT_BUCKET: ok"
retry_http "MinIO console HTTPS gateway" "https://dbs.home.arpa:${MINIO_CONSOLE_PORT}/" --insecure --resolve "dbs.home.arpa:${MINIO_CONSOLE_PORT}:127.0.0.1"

printf '\n===== ElasticMQ =====\n'
retry_elasticmq

printf '\n===== ElasticMQ UI =====\n'
retry_http "ElasticMQ UI HTTPS gateway" "https://dbs.home.arpa:${ELASTICMQ_UI_PORT}/" --insecure --resolve "dbs.home.arpa:${ELASTICMQ_UI_PORT}:127.0.0.1"

printf '\nAll checks completed.\n'
