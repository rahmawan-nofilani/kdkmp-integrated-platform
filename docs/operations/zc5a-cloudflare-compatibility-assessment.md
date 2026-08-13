# ZC-5A — Cloudflare Workers compatibility assessment

Status: BUILD COMPATIBILITY PROVEN VIA RUNNER-ONLY EDGE BRIDGE / LOCAL RUNTIME STILL REQUIRED / NO CLOUDFLARE ACCOUNT ACTIVATION

## Purpose

Assess whether the current KDKMP Next.js application can be transformed for Cloudflare Workers using the current OpenNext path without deploying anything or activating Cloudflare storage/services.

This phase is deliberately separate from a real Cloudflare pilot deployment.

## Current repository baseline

- Next.js: `16.3.0`
- React: `19.0.0`
- Node engine: `>=22.0.0`
- Supabase SSR: `0.12.4`
- Supabase JS: `2.111.0`
- App Router is in use.
- `src/proxy.ts` is present and delegates session refresh to `src/lib/supabase/proxy.ts`.
- no explicit `export const runtime = "edge"` declaration was found by the ZC-5A static scan.
- no `@vercel/*` runtime package import was found by the ZC-5A static scan.

## Current upstream compatibility facts

Cloudflare's current Next.js Workers guide uses `@opennextjs/cloudflare` and requires the `nodejs_compat` compatibility flag. Cloudflare recommends Workers, rather than Pages, for full-stack SSR Next.js applications.

The current OpenNext Cloudflare documentation states that all minor and patch releases of Next.js 16 are supported. It supports standard Middleware but does not yet support Node Middleware.

Next.js 16 changed `proxy.ts` to the Node.js runtime and does not allow `proxy.ts` to configure a different runtime. Next.js 16 still permits the deprecated `middleware.ts` convention when an Edge-runtime interception layer is required.

Supabase's current Next.js SSR guidance still requires a request interception layer to refresh expired Auth tokens and write refreshed cookies. It recommends `supabase.auth.getClaims()` and warns against treating the cookie session alone as authorization. KDKMP already follows this model and also enforces authorization in protected server code, so ZC-5A does not remove session refresh to make Cloudflare compile.

## Baseline failure — blocker proven

Cloudflare OpenNext Build Proof run #1 used the actual repository, Next.js `16.3.0`, `@opennextjs/cloudflare@1.20.2`, and Wrangler `4.94.0`.

The ordinary Next.js production build completed successfully, including TypeScript and route generation. OpenNext then stopped with the explicit adapter error:

`Node.js middleware is not currently supported. Consider switching to Edge Middleware.`

Therefore the demonstrated blocker is the Node-runtime request interception produced by `src/proxy.ts`, not Next.js `16.3.0` or the application build itself.

## Runner-only Edge compatibility bridge — PASS

A later proof kept the tracked authentication source unchanged and performed this transformation only inside the disposable GitHub runner:

1. save tracked `src/proxy.ts`;
2. create temporary `src/middleware.ts` with the identical body/matcher and rename only the exported request function from `proxy` to `middleware`;
3. remove `src/proxy.ts` only inside the disposable workspace;
4. run the OpenNext build;
5. restore original tracked `src/proxy.ts` and remove the temporary middleware file;
6. prove tracked `src` is clean again.

This proof passed.

Verified results:

- Next.js `16.3.0` production build: PASS;
- OpenNext Cloudflare transformation: PASS;
- `.open-next/worker.js`: generated;
- tracked Next.js source restored cleanly: PASS;
- Wrangler `deploy --dry-run`: PASS;
- Worker upload before compression: `6812.16 KiB`;
- Worker gzip size: `1387.49 KiB`;
- current Workers Free compressed limit: `3 MB`;
- static assets detected: `18`;
- persistent Cloudflare bindings: none; only the generated static `ASSETS` binding;
- Cloudflare account touched: false;
- Cloudflare storage touched: false;
- deployment attempted: false;
- secrets consumed: false.

The gzip bundle is therefore well below the current Workers Free size ceiling. This is build compatibility evidence only; it is not proof of login/session behavior on Workers.

## Pinned build-proof toolchain

ZC-5A CI installs the following only inside the disposable GitHub runner:

- `@opennextjs/cloudflare@1.20.2`
- `wrangler@4.94.0`

These packages are not added to `package.json` or `package-lock.json` in this phase.

The temporary Wrangler config contains only the Worker entry point, static assets, `nodejs_compat`, and a fixed compatibility date. It contains no R2, D1, KV, Durable Object or other persistent binding.

## Compatibility matrix

| Area | ZC-5A status | Remaining gate |
|---|---|---|
| Next.js 16.3.0 | BUILD PASS | local Workers runtime |
| App Router / RSC / SSR | BUILD PASS | local Workers runtime |
| Route handlers | BUILD PASS | `/api/health` local runtime test |
| Server Actions | BUILD PASS | authenticated local runtime test |
| Supabase SSR server client | BUILD PASS ONLY | login/session refresh runtime test |
| tracked `src/proxy.ts` | NODE MIDDLEWARE BLOCKER | cannot be used directly by current OpenNext |
| Edge middleware bridge | BUILD PASS | runtime auth/cookie behavior must be proven |
| Explicit Edge runtime in app routes | CLEAR | continue static scan |
| Vercel-specific runtime packages | CLEAR | continue static scan |
| Worker compressed size | PASS | `1387.49 KiB` < current Free limit |
| R2 cache | DISABLED | remains unauthorized |
| Cloudflare account/deployment | DISABLED | separate owner checkpoint |
| Custom domain | DISABLED | not needed yet |

## Security/dependency observation

The baseline application `npm ci` reported zero vulnerabilities in the application dependency graph. The ephemeral OpenNext/Wrangler probe installation reported six audit findings in its disposable dependency tree (`1 low`, `5 high`) plus deprecation warnings from transitive packages.

The probe packages are therefore not promoted to permanent application dependencies in ZC-5A. A focused dependency review is required before any adapter/tooling is committed for a deployable pilot.

## Explicit non-scope

ZC-5A does not:

- log in to Cloudflare;
- create a Cloudflare account or Worker;
- deploy to `workers.dev`;
- create R2/D1/KV/DO resources;
- create secrets;
- connect a domain;
- change Vercel;
- change Supabase schema or data;
- change production infrastructure;
- authorize billing or paid services.

## Official references checked for this assessment

- Cloudflare Workers Next.js guide: `https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/`
- Cloudflare Workers limits: `https://developers.cloudflare.com/workers/platform/limits/`
- Cloudflare Vercel-to-Workers migration guide: `https://developers.cloudflare.com/workers/static-assets/migration-guides/vercel-to-workers/`
- OpenNext Cloudflare documentation: `https://opennext.js.org/cloudflare`
- OpenNext existing-app setup: `https://opennext.js.org/cloudflare/get-started`
- Next.js 16 upgrade guide: `https://nextjs.org/docs/app/guides/upgrading/version-16`
- Supabase SSR client guide: `https://supabase.com/docs/guides/auth/server-side/creating-a-client`

## Decision after ZC-5A

Build compatibility is now proven with the runner-only Edge middleware bridge. The next safe phase is a local Workers runtime rehearsal that keeps all Cloudflare remote/account actions disabled and proves `/api/health`, public rendering, middleware execution, and Supabase cookie/session semantics before any tracked auth-source change or remote pilot.

R2 remains disabled regardless of runtime-test outcome.
