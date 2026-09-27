#!/usr/bin/env bash
set -Eeuo pipefail

: "${DEPLOY_ENV_FILE:?DEPLOY_ENV_FILE is required}"
if [[ -f "$DEPLOY_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV_FILE"
  set +a
fi
: "${BACKUP_ROOT:?BACKUP_ROOT is required}"
: "${ROLLBACK_STATE_DIR:?ROLLBACK_STATE_DIR is required}"

set_github_result(){ local result="$1"; if [[ -n "${GITHUB_ENV:-}" ]]; then echo "ROLLBACK_RESULT=$result" >> "$GITHUB_ENV"; fi; }
if [[ ! -f "$ROLLBACK_STATE_DIR/has-rollback" ]] || [[ "$(cat "$ROLLBACK_STATE_DIR/has-rollback")" != "true" ]]; then
  echo "::error::Deployment failed and no previous managed DB deployment was available for rollback."
  set_github_result "unavailable"; exit 0
fi
if [[ ! -d "$ROLLBACK_STATE_DIR/source" ]] || [[ ! -f "$ROLLBACK_STATE_DIR/runtime.env" ]]; then
  echo "::error::Rollback state is incomplete."; set_github_result "failed"; exit 1
fi

echo "::group::Failed candidate diagnostics"
set +e
docker compose --env-file "$DEPLOY_ENV_FILE" --profile '*' ps --all
docker compose --env-file "$DEPLOY_ENV_FILE" --profile '*' logs --no-color --tail=200
set -e
echo "::endgroup::"

if [[ -f "$ROLLBACK_STATE_DIR/new-backup-path.txt" ]]; then candidate_backup="$(cat "$ROLLBACK_STATE_DIR/new-backup-path.txt")"; rm -rf -- "$candidate_backup"; fi
if [[ -d "$ROLLBACK_STATE_DIR/previous-backup" && -f "$ROLLBACK_STATE_DIR/previous-backup-path.txt" ]]; then
  previous_backup_name="$(basename "$(cat "$ROLLBACK_STATE_DIR/previous-backup-path.txt")")"
  previous_backup_destination="$BACKUP_ROOT/$previous_backup_name"
  if [[ ! -d "$previous_backup_destination" ]]; then mkdir -p "$BACKUP_ROOT"; cp -a "$ROLLBACK_STATE_DIR/previous-backup" "$previous_backup_destination"; echo "Restored previous successful backup: $previous_backup_destination"; fi
fi

install -m 600 "$ROLLBACK_STATE_DIR/runtime.env" "$DEPLOY_ENV_FILE"
pushd "$ROLLBACK_STATE_DIR/source" >/dev/null
DEPLOY_ENV_FILE="$DEPLOY_ENV_FILE" bash ./scripts/start.sh --wait
DEPLOY_ENV_FILE="$DEPLOY_ENV_FILE" bash ./scripts/smoke-test.sh rollback
popd >/dev/null
set_github_result "success"
echo "::error::Candidate DB deployment failed. The last successful Compose source and runtime env were restored automatically."
echo "Rollback completed successfully. Docker volumes were preserved. The GitHub workflow intentionally remains failed."
