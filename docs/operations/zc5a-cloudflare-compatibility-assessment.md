# ZC-5A — Cloudflare Workers compatibility assessment

Status: NODE MIDDLEWARE BLOCKER PROVEN / EDGE BRIDGE PROBE IN PROGRESS / NO CLOUDFLARE ACCOUNT ACTIVATION

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

Supabase's current Next.js SSR guidance still requires a request interception layer to refresh expired Auth tokens and write refreshed cookies. It recommends `supabase.auth.getClaims()` and warns against treating the cookie session alone as authorization. KDKMP already follows this model and also enforces authorization in protected server code, so ZC-5A will not remove session refresh to make Cloudflare compile.

## Proven baseline result

Cloudflare OpenNext Build Proof run #1 used the actual repository, Next.js `16.3.0`, `@opennextjs/cloudflare@1.20.2`, and Wrangler `4.94.0`.

The ordinary Next.js production build completed successfully, including TypeScript and route generation. OpenNext then stopped with the explicit adapter error:

`Node.js middleware is not currently supported. Consider switching to Edge Middleware.`

Therefore:

- Next.js `16.3.0` itself is not the demonstrated blocker;
- application compilation is not the demonstrated blocker;
- the demonstrated blocker is the Node-runtime request interception produced by `src/proxy.ts`;
- Wrangler dry-run did not run after the failed build;
- no Cloudflare account, deployment, or storage was touched.

## Runner-only Edge compatibility bridge

The next ZC-5A proof does not modify the tracked authentication source.

Inside the disposable GitHub runner only, CI will:

1. save the tracked `src/proxy.ts`;
2. create `src/middleware.ts` with the identical body/matcher and rename only the exported request function from `proxy` to `middleware`;
3. remove `src/proxy.ts` only from the disposable workspace;
4. run the OpenNext build;
5. restore the original tracked `src/proxy.ts` and remove the temporary middleware file;
6. prove `git status` is clean for tracked `src` before the job finishes.

This tests the smallest officially documented compatibility bridge without yet changing the working Vercel application.

## Pinned build-proof toolchain

ZC-5A CI installs the following only inside the disposable GitHub runner:

- `@opennextjs/cloudflare@1.20.2`
- `wrangler@4.94.0`

These packages are not added to `package.json` or `package-lock.json` in this phase.

The proof creates temporary `open-next.config.ts` and `wrangler.jsonc` files in the runner. The Wrangler config has only:

- `.open-next/worker.js` entry point;
- `.open-next/assets` static assets;
- `nodejs_compat`;
- a fixed compatibility date.

It contains no R2, D1, KV, Durable Object or other persistent binding.

## Compatibility matrix

| Area | ZC-5A status | Gate |
|---|---|---|
| Next.js 16.3.0 baseline | PARTIAL PASS | native `next build` passed inside OpenNext run #1 |
| App Router / RSC / SSR | BUILD-COMPATIBLE SO FAR | OpenNext transformation still depends on middleware bridge |
| Route handlers | BUILD-COMPATIBLE SO FAR | later `/api/health` runtime test required |
| Server Actions | BUILD-COMPATIBLE SO FAR | authenticated action runtime test required later |
| Supabase SSR server client | COMPATIBILITY RISK | login/session refresh must be proven later |
| `src/proxy.ts` session refresh | BLOCKED AS NODE MIDDLEWARE | run #1 produced explicit OpenNext failure |
| runner-only Edge middleware bridge | PROBE | OpenNext build + later runtime auth test |
| Explicit Edge runtime in app routes | CLEAR | static scan returns none |
| Vercel-specific runtime packages | CLEAR | static scan returns none |
| Worker compressed size | PROBE | Wrangler dry-run must stay below Workers Free 3 MiB compressed limit |
| R2 cache | DISABLED | not authorized; no R2 binding in ZC-5A |
| Cloudflare account/deployment | DISABLED | separate explicit owner checkpoint |
| Custom domain | DISABLED | not needed for build proof |

## CI proof sequence

1. install application dependencies from the lockfile;
2. run repository static compatibility checks;
3. install pinned OpenNext + Wrangler in `node_modules` only;
4. prove `package.json` and `package-lock.json` remain byte-identical;
5. create temporary zero-binding Cloudflare/OpenNext config;
6. create the runner-only Edge middleware bridge;
7. run `opennextjs-cloudflare build`;
8. restore tracked Next.js source and prove it is unchanged;
9. if build succeeds, run Wrangler with `deploy --dry-run` only;
10. inspect compressed-size output and keep it below the current Workers Free 3 MiB compressed limit;
11. prove tracked app/package files remain unchanged.

A build failure is a valid ZC-5A result and must be investigated rather than bypassed.

## Security/dependency observation

The baseline application `npm ci` reported zero vulnerabilities in the application dependency graph. The ephemeral OpenNext/Wrangler probe installation reported additional audit findings in its disposable dependency tree. Those probe packages are therefore not promoted to permanent application dependencies in ZC-5A. A separate dependency review is required before any adapter/tooling is committed for a deployable pilot.

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

- If the runner-only Edge bridge build fails: investigate only the next demonstrated incompatibility.
- If the runner-only Edge bridge build passes: do not automatically change auth source. First prove Wrangler size and local Worker runtime behavior, then propose a reviewed compatibility change that preserves Vercel and Supabase semantics.

R2 remains disabled regardless of build outcome.
