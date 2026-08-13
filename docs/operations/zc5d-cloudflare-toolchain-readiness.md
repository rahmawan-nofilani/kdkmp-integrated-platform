# ZC-5D — Cloudflare toolchain and Free-plan readiness

Status: LOCAL TOOLCHAIN/RUNTIME PROOF PASSED / REMOTE PILOT NOT AUTHORIZED

## Verified proof

The Cloudflare proof workflow was re-run with the current stable probe stack:

- Next.js 16.3.0
- @opennextjs/cloudflare 1.20.2
- Wrangler 4.122.0
- compatibility date 2026-08-11
- no explicit nodejs_compat flag; the selected compatibility date enables Node.js compatibility by default

The tracked application source is not changed by this phase. The existing runner-only Edge middleware bridge remains a compatibility proof because OpenNext still does not support Next.js Node Middleware.

Verified CI results:

- application dependency install/audit: PASS, 0 vulnerabilities
- Application CI build/typecheck/audit: PASS
- OpenNext build: PASS
- Wrangler deploy --dry-run: PASS
- compressed Worker size: 1387.44 KiB
- internal compressed-size warning budget: 2304 KiB (75% of the 3 MiB Free-plan ceiling)
- local workerd runtime: PASS
- /api/health: HTTP 200
- /: HTTP 307 to /dashboard
- /login: HTTP 200
- package.json/package-lock.json unchanged by ephemeral probe installation
- tracked src restored clean after runner-only compatibility bridge

## Free-plan gates

Current Cloudflare Workers Free limits relevant to the pilot include:

- 100,000 dynamic Worker requests per day
- 10 ms CPU time per invocation
- 128 MB memory
- 3 MiB compressed Worker size

The size gate is currently PASS with substantial margin.

The 10 ms CPU limit is NOT proven by local wall-clock timing. Local workerd timing is not treated as equivalent to Cloudflare production CPU accounting. CPU usage must be measured during a separately authorized remote Workers Free pilot before any cutover decision.

## Remaining gates before remote pilot authorization

1. Resolve or formally accept the Next.js 16 proxy.ts / OpenNext Node Middleware incompatibility. The current Edge bridge is runner-only proof, not the production auth architecture.
2. Complete an end-to-end auth/session refresh regression proof without exposing or logging session material.
3. Keep server-side authorization through requireAccessContext() as a second guard; Proxy/Middleware must never be the sole authorization boundary.
4. Perform remote Workers Free CPU/request measurements only after explicit owner authorization.
5. Re-check Worker size, route behavior, request volume, error rate, and CPU before considering any cutover.

## Safety boundary

This phase does not authorize or perform:

- Cloudflare account/service activation that requires owner acceptance
- remote deployment
- production cutover
- R2 creation or use
- paid storage or paid plan activation
- custom-domain purchase
- Supabase schema/data changes
- production real-data onboarding

R2 remains NOT AUTHORIZED / NOT ACTIVATED.
