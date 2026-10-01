#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"
export MIX_ENV=e2e
export DOCKD_DB_NAME="${DOCKD_E2E_DB_NAME:-dockd_e2e}"
export DOCKD_DB_USER="${DOCKD_DB_USER:-dockd}"
export DOCKD_DB_PASSWORD="${DOCKD_DB_PASSWORD:-dockd}"
export DOCKD_DB_HOST="${DOCKD_DB_HOST:-localhost}"
export DOCKD_DB_PORT="${DOCKD_DB_PORT:-5432}"
export PORT="${PORT:-4460}"
export BASE_URL="${BASE_URL:-http://localhost:${PORT}}"

mix ecto.create --quiet
mix ecto.migrate --quiet
mix run priv/repo/e2e_seeds.exs
# A fresh checkout (CI) has no priv/static/assets: without the bundles the page
# never loads app.js and LiveView never connects. Only skip the rebuild when the
# bundle exists but is not ours to rewrite.
css=priv/static/assets/css/app.css
if [[ ! -e "$css" || -w "$css" ]]; then
  MIX_ENV=dev mix deps.get
  MIX_ENV=dev mix assets.setup
  MIX_ENV=dev mix assets.build
fi

server_log="${TMPDIR:-/tmp}/dockd-e2e-server.log"
MIX_ENV=e2e mix phx.server >"$server_log" 2>&1 &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 60); do
  if curl --fail --silent "${BASE_URL}/health" >/dev/null; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$server_log"
    exit 1
  fi
  sleep 1
done

curl --fail --silent "${BASE_URL}/health" >/dev/null
npm --prefix e2e ci
(cd e2e && npx playwright test)
