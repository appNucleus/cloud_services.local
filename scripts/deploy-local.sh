#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
export DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-$HOME/.config/db.local/runtime.env}"
export ROLLBACK_STATE_DIR="${ROLLBACK_STATE_DIR:-${TMPDIR:-/tmp}/db-local-rollback-$USER}"
export GITHUB_SHA="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo manual)}"
export GITHUB_RUN_ID="${GITHUB_RUN_ID:-manual-$(date +%s)}"
export GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"

mkdir -p "$(dirname "$DEPLOY_ENV_FILE")"
if [[ ! -f "$DEPLOY_ENV_FILE" ]]; then install -m 600 .env.example "$DEPLOY_ENV_FILE"; else chmod 600 "$DEPLOY_ENV_FILE" 2>/dev/null || true; fi

set -a
# shellcheck disable=SC1090
source "$DEPLOY_ENV_FILE"
set +a
export ACTIONS_ROOT="${ACTIONS_ROOT:-$HOME/actions_db.local}"
export BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backup_db.local}"
mkdir -p "$ACTIONS_ROOT" "$BACKUP_ROOT"

rollback_on_error(){ local original_status=$?; trap - ERR; echo "Local DB deployment failed with exit code $original_status. Attempting rollback..." >&2; bash ./scripts/rollback-release.sh || true; exit "$original_status"; }
trap rollback_on_error ERR

echo "Checking shell-script syntax..."
for script in scripts/*.sh; do bash -n "$script"; done
bash ./scripts/verify-server.sh
bash ./scripts/sync-runtime-env.sh
bash ./scripts/validate-runtime-env.sh
bash ./scripts/generate-dashboard-state.sh

# shellcheck source=common.sh
source ./scripts/common.sh
load_runtime_env
configure_service_selection
if service_enabled postgres; then bash ./scripts/generate-pgadmin-config.sh; fi
if service_enabled cognito; then bash ./scripts/generate-cognito-config.sh; fi
compose config >/dev/null

bash ./scripts/prepare-rollback.sh
bash ./scripts/start.sh --wait
bash ./scripts/smoke-test.sh candidate
bash ./scripts/create-success-backup.sh
compose_all_profiles ps -a
trap - ERR
echo "DB deployment completed successfully."
