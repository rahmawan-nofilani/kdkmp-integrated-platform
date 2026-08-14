# ZC-5H — Cloudflare DEVELOPMENT analytics read-only gate

Status: IMPLEMENTATION PREPARED / REMOTE ANALYTICS DEPENDS ON READ-ONLY TOKEN

## Purpose

Measure the already deployed DEVELOPMENT pilot Worker without creating, updating, deleting, or rebinding any Cloudflare resource.

Target Worker:

- `kdkmp-development-pilot`
- `https://kdkmp-development-pilot.nofilanirahmawan.workers.dev`

The query uses Cloudflare GraphQL Analytics `workersInvocationsAdaptive` for the selected Worker and reads:

- requests
- errors
- subrequests
- invocation status
- `cpuTimeP50`
- `cpuTimeP99`

## Credential boundary

The analytics workflow must use a dedicated repository secret:

- `CLOUDFLARE_ANALYTICS_TOKEN`

Expected Cloudflare permission:

- Account → Account Analytics → Read

The existing deployment token is intentionally not reused for analytics. The analytics token must not include Workers Scripts Edit, R2 write, KV write, D1 write, DNS write, billing write, or other mutation permissions.

If the analytics secret is absent, the workflow records:

- `analytics_secret_present=false`
- `analytics_gate=BLOCKED_SECRET_MISSING`

and performs no analytics query.

## Controlled sample

When the analytics token exists, the push-to-main workflow generates only 20 unauthenticated GET requests against the DEVELOPMENT pilot:

- 5 × `/api/health` expecting 200
- 5 × `/login` expecting 200
- 5 × `/` expecting 307
- 5 × `/dashboard` expecting 307

This is a tiny read-only traffic sample. It does not create application records, alter Supabase data, change Cloudflare configuration, activate storage, or perform a production cutover.

## Fail-closed interpretation

The verifier never invents a CPU unit. It logs Cloudflare GraphQL CPU quantiles as native raw values and explicitly records:

- `cpu_quantile_unit=cloudflare_graphql_native_not_assumed`
- `cpu_10ms_threshold_decision=NOT_AUTOMATED_UNTIL_UNIT_IS_VERIFIED`

This prevents a false PASS caused by silently assuming whether the GraphQL quantile values are milliseconds or another unit.

The preliminary analytics states are:

- `BLOCKED_SECRET_MISSING`: dedicated read-only analytics token is not available.
- `BLOCKED_QUERY_FAILED`: API/token/permission/schema query failed.
- `INSUFFICIENT_DATA`: no Worker invocation rows were returned.
- `INSUFFICIENT_SAMPLE`: fewer than 10 requests were returned.
- `FAIL_RUNTIME_ERRORS`: GraphQL reports errors or `exceededResources` requests.
- `MEASUREMENT_COLLECTED`: at least 10 requests were measured with no reported runtime errors/resource-exceeded requests; CPU threshold still requires unit verification before a final Free-plan PASS.

## Zero-cost safety boundary

This gate does not authorize or perform:

- Worker deploy/redeploy/delete/rollback
- Cloudflare resource creation or update
- R2/KV/D1/Durable Objects/Hyperdrive/Queues
- custom-domain or DNS changes
- Workers Paid activation
- billing changes
- production cutover
- production data onboarding
- Supabase schema/data writes
- authenticated-session credential handling

The authenticated login/session E2E gate remains separate. No user password, access token, refresh token, or session cookie is requested or logged by ZC-5H.

## Completion criteria

ZC-5H is complete only when:

1. static self-test passes;
2. dedicated analytics token is available and GraphQL query succeeds;
3. request/error/resource-exceeded evidence is collected;
4. CPU P50/P99 values are captured;
5. the unit/threshold interpretation is verified against Cloudflare's current authoritative behavior before deciding whether the 10 ms Workers Free CPU gate passes;
6. no Cloudflare or database mutation occurs.
