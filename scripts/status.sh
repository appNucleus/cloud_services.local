#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
load_runtime_env
configure_service_selection
cd "$repo_root"
echo "Platform: ${PLATFORM_HOSTNAME:-aws.home.arpa}"
echo "Enabled profiles: ${COMPOSE_PROFILES:-<none>}"
compose_all_profiles ps -a
