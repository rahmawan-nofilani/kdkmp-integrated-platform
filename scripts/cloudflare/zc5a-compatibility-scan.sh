#!/usr/bin/env bash
set -euo pipefail

for cmd in node grep find; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Required command missing: $cmd" >&2; exit 1; }
done

NEXT_VERSION="$(node -p "require('./package.json').dependencies.next")"
NODE_ENGINE="$(node -p "require('./package.json').engines.node")"

case "$NEXT_VERSION" in
  16.*) ;;
  *) echo "Unexpected Next.js version for ZC-5A baseline: $NEXT_VERSION" >&2; exit 1 ;;
esac

EDGE_RUNTIME_MATCHES="$(grep -RIlE "export[[:space:]]+const[[:space:]]+runtime[[:space:]]*=[[:space:]]*['\"]edge['\"]" src --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' 2>/dev/null || true)"
if [ -n "$EDGE_RUNTIME_MATCHES" ]; then
  echo "Explicit Next.js edge runtime declarations detected:" >&2
  printf '%s\n' "$EDGE_RUNTIME_MATCHES" >&2
  exit 1
fi

VERCEL_PACKAGE_MATCHES="$(grep -RIlE "from[[:space:]]+['\"]@vercel/|require\(['\"]@vercel/" src --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' 2>/dev/null || true)"
if [ -n "$VERCEL_PACKAGE_MATCHES" ]; then
  echo "Vercel-specific runtime package imports detected:" >&2
  printf '%s\n' "$VERCEL_PACKAGE_MATCHES" >&2
  exit 1
fi

PROXY_PRESENT=false
if [ -f src/proxy.ts ]; then
  PROXY_PRESENT=true
fi

SUPABASE_PROXY_PRESENT=false
if [ -f src/lib/supabase/proxy.ts ]; then
  SUPABASE_PROXY_PRESENT=true
fi

printf 'next_version=%s\n' "$NEXT_VERSION"
printf 'node_engine=%s\n' "$NODE_ENGINE"
printf 'explicit_edge_runtime=false\n'
printf 'vercel_runtime_imports=false\n'
printf 'next_proxy_present=%s\n' "$PROXY_PRESENT"
printf 'supabase_session_proxy_present=%s\n' "$SUPABASE_PROXY_PRESENT"
printf 'cloudflare_account_touched=false\n'
printf 'cloudflare_storage_touched=false\n'
printf 'deployment_attempted=false\n'
