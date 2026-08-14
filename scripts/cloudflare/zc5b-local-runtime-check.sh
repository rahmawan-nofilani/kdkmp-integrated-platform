#!/usr/bin/env bash
set -euo pipefail

PORT="${ZC5B_PORT:-8787}"
LOG="${ZC5B_PREVIEW_LOG:-/tmp/zc5b-preview.log}"
BASE_URL="http://127.0.0.1:${PORT}"

npx --no-install opennextjs-cloudflare preview --port "$PORT" >"$LOG" 2>&1 &
PID=$!
cleanup() {
  kill "$PID" >/dev/null 2>&1 || true
  wait "$PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

show_diagnostics() {
  echo '--- local preview log tail ---' >&2
  tail -n 120 "$LOG" >&2 || true
  echo '--- end local preview log tail ---' >&2
}

READY=false
for _ in $(seq 1 60); do
  HEALTH_CODE="$(curl --silent --show-error --output /tmp/zc5b-health.json --write-out '%{http_code}' --max-time 2 "${BASE_URL}/api/health" 2>/tmp/zc5b-health-curl.err || true)"
  if [ "$HEALTH_CODE" = '200' ]; then
    READY=true
    break
  fi
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo 'Local Workers preview exited before becoming ready.' >&2
    cat /tmp/zc5b-health-curl.err >&2 || true
    show_diagnostics
    exit 1
  fi
  sleep 1
done

if [ "$READY" != true ]; then
  echo "Local Workers preview did not return health HTTP 200; last status=${HEALTH_CODE:-none}." >&2
  cat /tmp/zc5b-health-curl.err >&2 || true
  cat /tmp/zc5b-health.json >&2 || true
  show_diagnostics
  exit 1
fi

if ! python - <<'PY'
import json
from pathlib import Path
health = json.loads(Path('/tmp/zc5b-health.json').read_text())
assert health['status'] == 'ok'
assert health['application'] == 'KDKMP Integrated Management Platform'
PY
then
  echo 'Health JSON contract validation failed.' >&2
  cat /tmp/zc5b-health.json >&2 || true
  show_diagnostics
  exit 1
fi

ROOT_CODE="$(curl --silent --show-error --output /tmp/zc5b-root.html --dump-header /tmp/zc5b-root.headers --write-out '%{http_code}' --max-time 5 "${BASE_URL}/" 2>/tmp/zc5b-root-curl.err || true)"
if [ "$ROOT_CODE" != '307' ]; then
  echo "Root route contract failed; expected 307 to /dashboard, got status=${ROOT_CODE:-none}." >&2
  cat /tmp/zc5b-root-curl.err >&2 || true
  cat /tmp/zc5b-root.headers >&2 || true
  show_diagnostics
  exit 1
fi
if ! grep -Eiq '^location:[[:space:]]*/dashboard[[:space:]]*$' /tmp/zc5b-root.headers; then
  echo 'Root redirect target is not /dashboard.' >&2
  cat /tmp/zc5b-root.headers >&2 || true
  show_diagnostics
  exit 1
fi

LOGIN_CODE="$(curl --silent --show-error --output /tmp/zc5b-login.html --write-out '%{http_code}' --max-time 5 "${BASE_URL}/login" 2>/tmp/zc5b-login-curl.err || true)"
if [ "$LOGIN_CODE" != '200' ]; then
  echo "Public login route failed; status=${LOGIN_CODE:-none}." >&2
  cat /tmp/zc5b-login-curl.err >&2 || true
  head -c 2000 /tmp/zc5b-login.html >&2 || true
  echo >&2
  show_diagnostics
  exit 1
fi

DASHBOARD_CODE="$(curl --silent --show-error --output /tmp/zc5b-dashboard.html --dump-header /tmp/zc5b-dashboard.headers --write-out '%{http_code}' --max-time 5 "${BASE_URL}/dashboard" 2>/tmp/zc5b-dashboard-curl.err || true)"
if [ "$DASHBOARD_CODE" != '307' ]; then
  echo "Unauthenticated dashboard guard failed; expected 307 to /login, got status=${DASHBOARD_CODE:-none}." >&2
  cat /tmp/zc5b-dashboard-curl.err >&2 || true
  cat /tmp/zc5b-dashboard.headers >&2 || true
  show_diagnostics
  exit 1
fi
if ! grep -Eiq '^location:[[:space:]]*/login[[:space:]]*$' /tmp/zc5b-dashboard.headers; then
  echo 'Unauthenticated dashboard redirect target is not /login.' >&2
  cat /tmp/zc5b-dashboard.headers >&2 || true
  show_diagnostics
  exit 1
fi

echo 'health_status=200'
echo 'root_status=307'
echo 'root_redirect=/dashboard'
echo 'login_status=200'
echo 'unauth_dashboard_status=307'
echo 'unauth_dashboard_redirect=/login'
echo 'workerd_local_runtime=PASSED'
echo 'cloudflare_remote_touched=false'
echo 'deployment_attempted=false'
