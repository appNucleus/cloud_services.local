#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_runtime_env_file
load_runtime_env

required=(POSTGRES_PASSWORD PGADMIN_DEFAULT_PASSWORD REDIS_PASSWORD NEO4J_PASSWORD MINIO_ROOT_PASSWORD)
placeholder_count=0
echo "Runtime credential policy (values are never printed):"
for key in "${required[@]}"; do
  value="${!key:-}"
  if [[ -z "$value" ]]; then
    echo "::error::$key is empty; deployment cannot continue." >&2
    exit 1
  fi
  if [[ "$value" == change_me_* || "$value" == "CHANGE_ME" ]]; then
    echo "::warning::$key is still using the documented local-development placeholder."
    echo " - $key: set (placeholder)"
    placeholder_count=$((placeholder_count + 1))
  else
    echo " - $key: set (custom)"
  fi
done

if (( placeholder_count > 0 )); then
  echo "::warning::$placeholder_count runtime credential(s) still use local-development placeholders. Deployment is allowed for backward compatibility; replace them when convenient."
fi

if [[ "${ADMIN_UI_HOST_BIND:-127.0.0.1}" != "127.0.0.1" ]]; then
  echo "Refusing deployment: ADMIN_UI_HOST_BIND must remain 127.0.0.1; Caddy is the HTTPS boundary." >&2
  exit 1
fi

echo "Runtime environment validation: OK (no secret values were logged)"
