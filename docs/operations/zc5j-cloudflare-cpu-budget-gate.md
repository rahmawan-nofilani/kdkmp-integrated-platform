# ZC-5J — Cloudflare DEVELOPMENT CPU Budget Gate

Status: IN PROGRESS
Target: `kdkmp-development-pilot`
Scope: read-only Cloudflare Analytics only.

## Objective

Turn the previously collected Workers CPU quantiles into a reliable Free-plan readiness decision without assuming the unit of Cloudflare GraphQL fields.

## Method

1. Query `workersInvocationsAdaptive` for the existing DEVELOPMENT Worker over a bounded lookback window.
2. Aggregate the window by invocation status rather than timestamp so P50/P99 are representative of the selected window rather than a maximum of individual time buckets.
3. Query Cloudflare GraphQL schema introspection and inspect the live descriptions for `cpuTimeP50` and `cpuTimeP99` under the Workers invocations adaptive quantile type.
4. Accept a CPU unit only when the Cloudflare schema states it explicitly.
5. Convert the verified native unit to milliseconds.
6. Compare the measured window against the Workers Free HTTP CPU budget of 10 ms/invocation.

## Decision rules

- `PASS_WITHIN_FREE_10MS`: P50 and P99 are both at or below 10 ms, with no runtime/exceeded-resource errors.
- `CONDITIONAL_P99_OVER_FREE_10MS`: median remains within 10 ms but P99 exceeds it and no exceeded-resource terminations are observed. This requires more observation/optimization before final readiness.
- `FAIL_MEDIAN_OVER_FREE_10MS`: median CPU is above the Free-plan budget; zero-cost runtime is not considered reliable enough.
- `FAIL_EXCEEDED_RESOURCES` / `FAIL_RUNTIME_ERRORS`: Cloudflare reports runtime/resource failures.
- `BLOCKED_UNIT_UNVERIFIED`: schema metadata does not explicitly provide a supported unit; no threshold decision is made.

## Safety boundary

This gate performs GraphQL query operations only. It does not deploy or update a Worker, change bindings, activate R2/KV/D1/Durable Objects, change billing, use production data, modify Supabase, or authorize production cutover.
