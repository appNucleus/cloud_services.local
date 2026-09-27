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
compose_all_profiles down -v --remove-orphans
rm -rf -- "$(repo_path "$GENERATED_DIR")"
echo "Deleted all stack data."
