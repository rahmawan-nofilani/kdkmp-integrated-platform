# ZC-5E — Cloudflare pre-pilot checkpoint

Status: READY FOR REVIEW / REMOTE PILOT NOT AUTHORIZED

Accepted evidence:
- Application CI is green on the ZC-5D merge.
- OpenNext 1.20.2 + Wrangler 4.122.0 build/dry-run is green.
- Local workerd route checks are green.
- Worker gzip size is about 1387.44 KiB, below the 2304 KiB internal warning budget.

Open gates before any production-cutover discussion:
1. Auth/session behavior must be proven end-to-end; source review alone is not enough.
2. The Next.js 16 Proxy versus current OpenNext Node Middleware limitation must have an explicit reviewed solution.
3. Workers Free CPU usage and request volume must be measured during a separately authorized parallel pilot.
4. The pilot must cover protected routes, SSR, Server Actions, RLS, POS DEVELOPMENT/demo flows, mobile behavior, and error states.

Binding safety rules:
- R2 remains NOT AUTHORIZED / NOT ACTIVATED.
- Paid Cloudflare services remain NOT AUTHORIZED.
- Production cutover remains NOT AUTHORIZED.
- Vercel DEVELOPMENT/preview remains intact during any future parallel pilot.
- No production real data and no destructive archive/pruning action are included.

A separate explicit owner authorization is required before a remote Cloudflare Workers Free pilot is created or bound.
