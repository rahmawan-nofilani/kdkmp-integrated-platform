# ZC-5I — Cloudflare DEVELOPMENT Functional/Auth Pilot Matrix

Status: FINAL FOR PILOT DECISION
Target: `kdkmp-development-pilot` on `workers.dev`
Scope: DEVELOPMENT pilot only. This is not a production cutover authorization.

## Verified runtime evidence

- Remote Worker deployment exists and is reachable on the Cloudflare `workers.dev` hostname.
- `/api/health` returns HTTP 200.
- `/` returns HTTP 307 to `/dashboard`.
- `/login` returns HTTP 200.
- `/dashboard` without an authenticated session returns HTTP 307 to `/login`.
- Owner performed an interactive DEVELOPMENT email/password login from the Cloudflare pilot hostname.
- Login succeeded and the dashboard rendered successfully.
- Browser address bar remained on the Cloudflare `workers.dev` hostname after authentication and dashboard navigation.
- Supabase Auth recorded a successful password login in the corresponding test window.
- Protected dashboard rendering exercises the server-side access-context path before content is rendered; the dashboard cannot render for an unauthenticated request.
- Application auth code uses SSR cookies and `supabase.auth.getClaims()` for JWT validation; protected server-side access remains enforced beyond the proxy layer.
- A no-session proxy fast path was added without weakening the protected Server Component guard; local and remote unauthenticated `/dashboard` checks remained fail-closed.
- Read-only Workers analytics completed successfully and reported request, error, exceeded-resource, and CPU metrics.
- Two post-optimization CPU samples reported zero request errors and zero exceeded-resource requests but median CPU above the strict Workers Free 10 ms/request budget on the tested routes.

## Attribution note

Supabase Auth log metadata for the successful login reported the existing Vercel DEVELOPMENT URL in the `referer` field even though the browser remained on the Cloudflare pilot hostname. Treat this as an observability/runtime-attribution anomaly retained for investigation, not as evidence that the browser left Cloudflare.

## Final classification

- Public Worker runtime: PASS
- Unauthenticated protected-route guard: PASS
- Interactive DEVELOPMENT login: PASS
- Authenticated dashboard render on Cloudflare hostname: PASS
- Basic authenticated access-context path: PASS
- Read-only Workers analytics: PASS
- Error / exceeded-resource observation in measured samples: PASS (0 / 0)
- Strict Workers Free CPU production gate: **NOT PASSED**
- Cloudflare DEVELOPMENT pilot: **PASS WITH PRODUCTION CPU EXCEPTION**
- Cloudflare Workers Free full-stack SSR production promotion: **NO-GO under current architecture**
- Production cutover: NOT AUTHORIZED / NOT PERFORMED
- Long-lived session refresh / expiry lifecycle: NOT PROVEN; deferred because the pilot is not being promoted to production.

## Owner browser sanity checks remaining

These checks do not change the CPU decision and do not authorize production promotion:

1. While authenticated on the Cloudflare dashboard, reload the page and confirm the session remains valid and the browser stays on the Cloudflare hostname.
2. Log out, then access `/dashboard` again and confirm the user is returned to the unauthenticated/login state.

## Binding safety boundaries

- R2 remains NOT AUTHORIZED and was not activated.
- Paid Cloudflare services remain NOT AUTHORIZED and were not activated.
- Custom domain remains NOT AUTHORIZED and was not configured.
- Production cutover remains NOT AUTHORIZED and was not performed.
- Production data remains NOT AUTHORIZED and was not used.
- Vercel DEVELOPMENT remains intact.
- No archive prune/delete/purge is authorized by this pilot.
- The one-time ZC-5J redeploy authorization was consumed and its executor/authorization marker were removed from `main`.

## Decision reference

See `docs/operations/zc5j-cloudflare-free-cpu-outcome.md` for the authorized redeploy, CPU samples, and final Free-plan CPU decision.
