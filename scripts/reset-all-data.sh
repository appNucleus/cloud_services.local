#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
load_runtime_env
GENERATED_DIR="${GENERATED_DIR:-./generated}"
cd "$repo_root"
echo "WARNING: This deletes ALL Docker volumes for this stack, including currently disabled service volumes."
echo "This should never be used from GitHub Actions deployment."
read -r -p "Type DELETE to continue: " answer
if [[ "$answer" != "DELETE" ]]; then
  echo "Cancelled."
  exit 0
fi
cognito_volume="${COGNITO_VOLUME_NAME:-db-cognito-data}"
compose_all_profiles down -v --remove-orphans
if docker volume inspect "$cognito_volume" >/dev/null 2>&1; then
  docker volume rm "$cognito_volume" >/dev/null
fi
rm -rf -- "$(repo_path "$GENERATED_DIR")"
echo "Deleted all stack data, including the external Cognito Local volume."
