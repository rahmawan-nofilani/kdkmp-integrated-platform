# ZC-5J — Cloudflare Workers Free CPU Outcome

Date: 2026-08-14

## Scope

This record closes the ZC-5J CPU remediation and re-measurement gate for the Cloudflare DEVELOPMENT pilot Worker `kdkmp-development-pilot`.

The user authorized exactly one redeploy of the existing DEVELOPMENT Worker for this CPU test. The authorization explicitly excluded R2, paid services, custom domains, production cutover, production data, database writes, Worker deletion, and rollback.

## Optimization under test

The application added a no-session fast path in `src/lib/supabase/proxy.ts`: when a request has no Supabase auth cookie, the Proxy skips `supabase.auth.getClaims()` session validation/refresh. Requests that carry a Supabase auth cookie continue to use the existing validation/refresh path. Protected Server Components continue to enforce `requireAccessContext()` and `getClaims()` independently.

The optimization was merged before the authorized redeploy at commit:

`ab0075e34e27e9b40f7ac244faa5efdbaf19911c`

## Authorized redeploy evidence

The first CLI invocation stopped before upload because the deployment message contained spaces. A read-only preflight subsequently proved that no remote write occurred:

- active Worker version remained `c72c898e-0853-407f-a395-03c52fae6353`;
- failed-attempt deployment marker count = 0;
- corrected deployment marker count = 0;
- active paid account subscription count = 0;
- existing binding types = `assets,plain_text`.

The corrected one-time redeploy then completed successfully:

- predeploy version: `c72c898e-0853-407f-a395-03c52fae6353`;
- postdeploy version: `d5c75ba1-78c6-4551-a6f6-e0da54865aa1`;
- deployment marker `ZC5J-CPU-20260814-ab0075e3` count = 1;
- Worker hostname remained `kdkmp-development-pilot.nofilanirahmawan.workers.dev`;
- compressed Worker size = 1387.57 KiB;
- route contract = PASS;
- postdeploy binding types = `assets,plain_text`;
- postdeploy active paid account subscription count = 0;
- R2 activated = false;
- paid service activated = false;
- custom domain configured = false;
- production cutover = false;
- production data used = false;
- database write attempted = false;
- Worker delete attempted = false;
- rollback attempted = false.

The single authorized redeploy is therefore **CONSUMED**. No additional deploy or redeploy is authorized by this record.

## CPU measurements

The route-isolation harness uses public GET requests plus read-only Cloudflare GraphQL analytics. CPU units were verified from the Cloudflare GraphQL schema as microseconds and converted to milliseconds. The dataset is adaptive, so route samples are diagnostic evidence; the decision requires repeated results rather than a single isolated quantile.

### Baseline before optimization redeploy

| Route | P50 CPU | P99 CPU | Errors | Exceeded resources |
| --- | ---: | ---: | ---: | ---: |
| `/api/health` | 8.639 ms | 164.570 ms | 0 | 0 |
| `/login` | 18.768 ms | 108.846 ms | 0 | 0 |
| `/` | 22.587 ms | 62.553 ms | 0 | 0 |
| `/dashboard` unauthenticated | 16.460 ms | 34.022 ms | 0 | 0 |

The root window contained extra requests and was treated as indicative rather than a clean isolated sample.

### Postdeploy sample 1

| Route | Coverage | P50 CPU | P99 CPU | Errors | Exceeded resources |
| --- | ---: | ---: | ---: | ---: | ---: |
| `/api/health` | 100% | 10.245 ms | 310.212 ms | 0 | 0 |
| `/login` | 100% | 26.345 ms | 376.253 ms | 0 | 0 |
| `/` | 80% | 32.861 ms | 97.825 ms | 0 | 0 |
| `/dashboard` unauthenticated | 90% | 21.660 ms | 41.003 ms | 0 | 0 |

### Postdeploy sample 2

| Route | Coverage | P50 CPU | P99 CPU | Errors | Exceeded resources |
| --- | ---: | ---: | ---: | ---: | ---: |
| `/api/health` | 95% | 11.152 ms | 325.896 ms | 0 | 0 |
| `/login` | 100% | 22.208 ms | 227.170 ms | 0 | 0 |
| `/` | 100% | 28.505 ms | 67.491 ms | 0 | 0 |
| `/dashboard` unauthenticated | 95% | 21.757 ms | 398.272 ms | 0 | 0 |

## Decision

**ZC-5J strict Cloudflare Workers Free CPU gate: NOT PASSED.**

Two independent postdeploy samples continued to show median CPU above the 10 ms/request Free-plan budget on the tested routes. The no-session Proxy fast path did not produce a sufficient reduction to justify a production promotion decision.

The DEVELOPMENT pilot itself remains functionally healthy in the observed checks:

- public health route responds successfully;
- login route responds successfully;
- root redirect contract remains correct;
- unauthenticated dashboard remains fail-closed and redirects to login;
- observed CPU samples reported zero request errors;
- observed CPU samples reported zero exceeded-resource requests;
- zero-cost account and binding boundaries remained intact.

## Operating position

1. Keep `kdkmp-development-pilot` as a DEVELOPMENT/pilot endpoint only.
2. Do not promote the current full-stack SSR architecture to Cloudflare Workers Free production on the basis of this pilot.
3. Do not weaken authentication or authorization controls merely to reduce CPU usage.
4. No further Cloudflare deploy/redeploy is authorized by ZC-5J.
5. Reconsider Cloudflare full-stack production only after a material runtime/architecture change followed by a fresh authorization and new measurements.
6. Continue to ZC-5K Final Zero-Cost Readiness & Operating Handoff with the Cloudflare production CPU gate explicitly recorded as not passed.
