#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ensure_runtime_env_file
load_runtime_env

source_dir="$(repo_path "${DASHBOARD_WWW_DIR:-./www}")"
output="$(repo_path "${DASHBOARD_RUNTIME_CONFIG:-./www/runtime-config.js}")"

[[ -f "$source_dir/index.html" ]] || { echo "Dashboard source is missing: $source_dir/index.html" >&2; exit 1; }
mkdir -p "$(dirname "$output")"

cat > "$output" <<EOF_JS
window.CLOUD_SERVICES_CONFIG = Object.freeze({
  hostname: "${PLATFORM_HOSTNAME:-aws.home.arpa}",
  services: Object.freeze({
    postgres: ${ENABLE_POSTGRES:-true},
    redis: ${ENABLE_REDIS:-true},
    neo4j: ${ENABLE_NEO4J:-true},
    minio: ${ENABLE_MINIO:-true},
    elasticmq: ${ENABLE_ELASTICMQ:-true},
    cognito: ${ENABLE_COGNITO:-true}
  }),
  ports: Object.freeze({
    postgres: ${POSTGRES_PORT:-5432},
    pgadmin: ${PGADMIN_PORT:-5050},
    redis: ${REDIS_PORT:-6379},
    redisinsight: ${REDISINSIGHT_PORT:-5540},
    neo4jHttp: ${NEO4J_HTTP_PORT:-7474},
    neo4jBolt: ${NEO4J_BOLT_PORT:-7687},
    minioApi: ${MINIO_API_PORT:-9000},
    minioConsole: ${MINIO_CONSOLE_PORT:-9001},
    elasticmqApi: ${ELASTICMQ_PORT:-9324},
    elasticmqUi: ${ELASTICMQ_UI_PORT:-9325},
    cognito: ${COGNITO_PORT:-9229},
    cognitoUi: ${COGNITO_UI_PORT:-9230}
  })
});
EOF_JS

chmod 0644 "$output"
echo "Generated dashboard runtime state: $output"
