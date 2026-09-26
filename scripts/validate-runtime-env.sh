#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_runtime_env_file
load_runtime_env

required=(POSTGRES_PASSWORD PGADMIN_DEFAULT_PASSWORD REDIS_PASSWORD NEO4J_PASSWORD MINIO_ROOT_PASSWORD)
for key in "${required[@]}"; do
  value="${!key:-}"
  if [[ -z "$value" ]]; then
    echo "Required runtime value is empty: $key" >&2
    exit 1
  fi
  if [[ "$value" == change_me_* || "$value" == "CHANGE_ME" ]]; then
    echo "Refusing deployment: $key still uses a documented placeholder password." >&2
    exit 1
  fi
done

if [[ "${ADMIN_UI_HOST_BIND:-127.0.0.1}" != "127.0.0.1" ]]; then
  echo "Refusing deployment: ADMIN_UI_HOST_BIND must remain 127.0.0.1; Caddy is the HTTPS boundary." >&2
  exit 1
fi

echo "Runtime environment validation: OK"
