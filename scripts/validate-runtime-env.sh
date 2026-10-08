#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_runtime_env_file
load_runtime_env

validate_bool() {
  local key="$1" value="${!1:-}"
  case "$value" in
    true|false) ;;
    *) echo "Refusing deployment: $key must be exactly 'true' or 'false' (found '${value:-<empty>}')." >&2; exit 1 ;;
  esac
}

for key in ENABLE_POSTGRES ENABLE_REDIS ENABLE_NEO4J ENABLE_MINIO ENABLE_ELASTICMQ ENABLE_COGNITO ENABLE_OPENSEARCH RUN_MINIO_INIT; do
  validate_bool "$key"
done

platform_hostname="${PLATFORM_HOSTNAME:-aws.home.arpa}"
if [[ ! "$platform_hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
  echo "Refusing deployment: PLATFORM_HOSTNAME must be a bare DNS hostname without scheme, path, or port." >&2
  exit 1
fi

cognito_port="${COGNITO_PORT:-9229}"
if [[ ! "$cognito_port" =~ ^[0-9]+$ ]] || (( cognito_port < 1 || cognito_port > 65535 )); then
  echo "Refusing deployment: COGNITO_PORT must be an integer from 1 to 65535." >&2
  exit 1
fi

if [[ "${ADMIN_UI_HOST_BIND:-127.0.0.1}" != "127.0.0.1" ]]; then
  echo "Refusing deployment: ADMIN_UI_HOST_BIND must remain 127.0.0.1; Caddy is the HTTPS boundary." >&2
  exit 1
fi

required=()
service_enabled postgres && required+=(POSTGRES_PASSWORD PGADMIN_DEFAULT_PASSWORD)
service_enabled redis && required+=(REDIS_PASSWORD)
service_enabled neo4j && required+=(NEO4J_PASSWORD)
service_enabled minio && required+=(MINIO_ROOT_PASSWORD)

placeholder_count=0
echo "Runtime credential policy for enabled services (values are never printed):"
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

if service_enabled opensearch; then
  initial_password="${OPENSEARCH_INITIAL_ADMIN_PASSWORD:-}"
  if (( ${#initial_password} < 12 )) || ! [[ "$initial_password" =~ [[:upper:]] && "$initial_password" =~ [[:lower:]] && "$initial_password" =~ [[:digit:]] && "$initial_password" =~ [[:punct:]] ]]; then
    echo "Refusing OpenSearch deployment: set a strong admin password (12+ characters with uppercase, lowercase, number, and special character)." >&2
    exit 1
  fi
fi

configure_service_selection
printf 'Enabled profiles: %s\n' "${COMPOSE_PROFILES:-<none>}"
echo "Platform hostname: $platform_hostname"

case "${VERIFY_HOST_CADDY:-auto}" in
  true|false|auto) ;;
  *)
    echo "Refusing deployment: VERIFY_HOST_CADDY must be true, false, or auto." >&2
    exit 1
    ;;
esac

echo "Runtime environment validation: OK (no secret values were logged)"
