# ZC-5I — Cloudflare DEVELOPMENT Functional/Auth Pilot Matrix

Status: IN PROGRESS
Target: `kdkmp-development-pilot` on `workers.dev`
Scope: DEVELOPMENT pilot only. This is not a production cutover authorization.

## Verified runtime evidence

- Remote Worker deployment exists and is reachable on the Cloudflare `workers.dev` hostname.
- `/api/health` returned HTTP 200 during the authorized remote pilot workflow.
- `/` returned HTTP 307 to `/dashboard`.
- `/login` returned HTTP 200.
- `/dashboard` without an authenticated session returned HTTP 307 to `/login`.
- Owner performed an interactive DEVELOPMENT email/password login from the Cloudflare pilot hostname.
- Login succeeded and the dashboard rendered successfully.
- Browser address bar remained on the Cloudflare `workers.dev` hostname after authentication and dashboard navigation.
- Supabase Auth recorded a successful password login at the corresponding test window.
- Application auth code uses SSR cookies and `supabase.auth.getClaims()` for JWT validation; protected server-side access remains enforced beyond the proxy layer.

## Attribution note

Supabase Auth log metadata for the successful login reported the existing Vercel DEVELOPMENT URL in the `referer` field even though the browser remained on the Cloudflare pilot hostname. Treat this as an observability/runtime-attribution anomaly to retain for investigation, not as evidence that the browser left Cloudflare.

Current classification:

- Public Worker runtime: PASS
- Unauthenticated protected-route guard: PASS
- Interactive DEVELOPMENT login: PASS
- Authenticated dashboard render on Cloudflare hostname: PASS
- Basic authenticated browser E2E: PASS
- Long-lived session refresh / expiry lifecycle: NOT YET PROVEN
- Cloudflare CPU/error analytics: BLOCKED until dedicated read-only analytics token is available

## Remaining functional checks before final Zero-Cost readiness

1. Confirm a normal browser refresh on an authenticated dashboard preserves the session and protected-route access.
2. Confirm logout invalidates the session and returns the user to the unauthenticated state.
3. Confirm one representative authorized read path governed by the existing access context/RLS works from the Cloudflare pilot.
4. Confirm one representative fail-closed authorization case remains denied.
5. Complete read-only Workers analytics for requests, errors, and CPU P50/P99 using the dedicated analytics token.
6. Record final PASS / CONDITIONAL / FAIL decision without changing Vercel DEVELOPMENT or enabling paid Cloudflare services.

## Binding safety boundaries

- R2 remains NOT AUTHORIZED.
- Paid Cloudflare services remain NOT AUTHORIZED.
- Custom domain remains NOT AUTHORIZED.
- Production cutover remains NOT AUTHORIZED.
- Production data remains NOT AUTHORIZED.
- Vercel DEVELOPMENT remains intact.
- No archive prune/delete/purge is authorized by this pilot.
