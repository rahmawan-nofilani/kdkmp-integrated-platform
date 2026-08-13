#!/usr/bin/env bash
set -euo pipefail

PORT="${ZC5B_PORT:-8787}"
LOG="${ZC5B_PREVIEW_LOG:-/tmp/zc5b-preview.log}"

npx --no-install opennextjs-cloudflare preview --port "$PORT" >"$LOG" 2>&1 &
PID=$!
cleanup() {
  kill "$PID" >/dev/null 2>&1 || true
  wait "$PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

READY=false
for _ in $(seq 1 60); do
  if curl --silent --show-error --fail --max-time 2 "http://127.0.0.1:${PORT}/api/health" >/tmp/zc5b-health.json 2>/dev/null; then
    READY=true
    break
  fi
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo 'Local Workers preview exited before becoming ready.' >&2
    cat "$LOG" >&2
    exit 1
  fi
  sleep 1
done

if [ "$READY" != true ]; then
  echo 'Local Workers preview did not become ready.' >&2
  cat "$LOG" >&2
  exit 1
fi

python - <<'PY'
import json
from pathlib import Path
health = json.loads(Path('/tmp/zc5b-health.json').read_text())
assert health['status'] == 'ok'
assert health['application'] == 'KDKMP Integrated Management Platform'
PY

ROOT_CODE="$(curl --silent --show-error --output /tmp/zc5b-root.html --write-out '%{http_code}' --max-time 5 "http://127.0.0.1:${PORT}/")"
test "$ROOT_CODE" = '200'

echo 'health_status=200'
echo "root_status=$ROOT_CODE"
echo 'workerd_local_runtime=PASSED'
echo 'cloudflare_remote_touched=false'
echo 'deployment_attempted=false'
