#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -n "${DEPLOY_ENV_FILE:-}" && -f "$DEPLOY_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV_FILE"
  set +a
fi

for command_name in docker git curl tar sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

docker version >/dev/null
docker compose version >/dev/null
docker ps >/dev/null

compose_version="$(docker compose version --short | sed 's/^v//')"
minimum_compose_version="2.20.0"
if [[ "$(printf '%s\n%s\n' "$minimum_compose_version" "$compose_version" | sort -V | head -n1)" != "$minimum_compose_version" ]]; then
  echo "Docker Compose >= $minimum_compose_version is required; found $compose_version" >&2
  exit 1
fi

check_path="${ACTIONS_ROOT:-$HOME}"
mkdir -p "$check_path"
free_kib="$(df -Pk "$check_path" | awk 'NR==2 {print $4}')"
free_gib=$((free_kib / 1024 / 1024))
min_free_gib="${MIN_FREE_DISK_GIB:-5}"
warn_free_gib="${WARN_FREE_DISK_GIB:-10}"
if (( free_gib < min_free_gib )); then
  echo "Insufficient free disk space: ${free_gib} GiB available; ${min_free_gib} GiB required." >&2
  exit 1
elif (( free_gib < warn_free_gib )); then
  echo "::warning::Low disk headroom: ${free_gib} GiB free (warning threshold ${warn_free_gib} GiB)."
fi

echo "Docker Engine:  OK"
echo "Docker Compose: OK ($compose_version)"
echo "Docker access:  OK"
echo "Git:            OK"
echo "curl:           OK"
echo "tar:            OK"
echo "sha256sum:      OK"
echo "Free disk:      ${free_gib} GiB"
