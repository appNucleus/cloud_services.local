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
DB_HOST_BIND="${DB_HOST_BIND:-0.0.0.0}"
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

cd "$repo_root"

printf '\n===== Containers =====\n'
compose ps

printf '\n===== Dashboard =====\n'
curl -fsS "http://${DASHBOARD_HOST_BIND}:${DASHBOARD_PORT}/" >/dev/null && echo "dashboard: ok"

printf '\n===== pgAdmin =====\n'
curl -fsS "http://127.0.0.1:${PGADMIN_PORT}/misc/ping" >/dev/null && echo "pgAdmin: ok"

printf '\n===== PostgreSQL =====\n'
docker exec "$POSTGRES_CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
docker exec "$POSTGRES_CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "CREATE EXTENSION IF NOT EXISTS vector; SELECT extname FROM pg_extension WHERE extname='vector';"

printf '\n===== Redis =====\n'
docker exec "$REDIS_CONTAINER_NAME" redis-cli -a "$REDIS_PASSWORD" ping

printf '\n===== RedisInsight =====\n'
curl -fsS "http://127.0.0.1:${REDISINSIGHT_PORT}/api/health/" >/dev/null && echo "RedisInsight: ok"

printf '\n===== Neo4j =====\n'
docker exec "$NEO4J_CONTAINER_NAME" cypher-shell -u "$NEO4J_USERNAME" -p "$NEO4J_PASSWORD" "RETURN 1 AS ok;"
curl -fsS "http://127.0.0.1:${NEO4J_HTTP_PORT}/" >/dev/null && echo "Neo4j Browser HTTP: ok"

printf '\n===== MinIO =====\n'
docker exec "$MINIO_CONTAINER_NAME" mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
if ! docker exec "$MINIO_CONTAINER_NAME" mc stat "local/$MINIO_DEFAULT_BUCKET" >/dev/null 2>&1; then
  echo "Required MinIO bucket is missing: $MINIO_DEFAULT_BUCKET" >&2
  exit 1
fi
echo "MinIO bucket $MINIO_DEFAULT_BUCKET: ok"
curl -fsS "http://127.0.0.1:${MINIO_CONSOLE_PORT}/" >/dev/null && echo "MinIO console: ok"

printf '\n===== ElasticMQ =====\n'
elasticmq_response="$(curl -fsS -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'Action=ListQueues&Version=2012-11-05' \
  "http://127.0.0.1:${ELASTICMQ_PORT}/")"
if [[ "$elasticmq_response" != *"ListQueuesResponse"* ]]; then
  echo "ElasticMQ SQS ListQueues check returned an unexpected response." >&2
  exit 1
fi
echo "elasticmq SQS API: ok"

printf '\n===== ElasticMQ UI =====\n'
curl -fsS "http://127.0.0.1:${ELASTICMQ_UI_PORT}/" >/dev/null && echo "elasticmq UI: ok"

printf '\nAll checks completed.\n'
