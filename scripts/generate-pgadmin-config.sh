#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_runtime_env_file
load_runtime_env

POSTGRES_DB="${POSTGRES_DB:-langgraph_app}"
POSTGRES_USER="${POSTGRES_USER:-langgraph_user}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-change_me_postgres_2026}"
PGADMIN_SERVERS_JSON="${PGADMIN_SERVERS_JSON:-./generated/pgadmin/servers.json}"

servers_json_path="$(repo_path "$PGADMIN_SERVERS_JSON")"
mkdir -p "$(dirname "$servers_json_path")"

cat > "$servers_json_path" <<JSON
{
  "Servers": {
    "1": {
      "Name": "db-postgres-pgvector",
      "Group": "Docker",
      "Host": "postgres",
      "Port": 5432,
      "MaintenanceDB": "${POSTGRES_DB}",
      "Username": "${POSTGRES_USER}",
      "Password": "${POSTGRES_PASSWORD}",
      "SSLMode": "prefer",
      "Favorite": true
    }
  }
}
JSON

chmod 600 "$servers_json_path"
echo "Generated pgAdmin server config: $PGADMIN_SERVERS_JSON"
