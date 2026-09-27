#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
load_runtime_env
cd "$repo_root"
compose_all_profiles logs -f --tail=200 "$@"
