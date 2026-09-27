#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ensure_runtime_env_file
load_runtime_env

output="$(repo_path "${COGNITO_CONFIG_FILE:-./generated/cognito/config.json}")"
mkdir -p "$(dirname "$output")"

cat > "$output" <<EOF_JSON
{
  "ServerConfig": {
    "hostname": "0.0.0.0",
    "port": 9229
  },
  "TokenConfig": {
    "IssuerDomain": "https://${PLATFORM_HOSTNAME:-aws.home.arpa}:${COGNITO_PORT:-9229}"
  }
}
EOF_JSON

chmod 0644 "$output"
echo "Generated Cognito Local configuration: $output"
