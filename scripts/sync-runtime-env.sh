#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ensure_runtime_env_file

# Add newly introduced keys without changing any existing server-specific value.
while IFS= read -r line; do
  [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
  key="${line%%=*}"
  if ! grep -qE "^${key}=" "$runtime_env_file"; then
    printf '\n%s\n' "$line" >> "$runtime_env_file"
    echo "Added missing runtime key: $key"
  fi
done < "$repo_root/.env.example"
chmod 600 "$runtime_env_file"
