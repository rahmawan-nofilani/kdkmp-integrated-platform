# ZC-5K — Final Zero-Cost Readiness & Operating Handoff

Date: 2026-08-14
Status: READY FOR OWNER HANDOFF — CLOUDFLARE FREE PRODUCTION NO-GO
Parent tracker: #58 — Zero-Cost Mode — Capacity, Backup, Archive & Cloudflare Pilot

## Executive decision

The Zero-Cost foundation and Cloudflare compatibility pilot have reached a defensible operating decision without enabling paid infrastructure, R2, a custom domain, production cutover, production data, or destructive archival actions.

The Cloudflare DEVELOPMENT pilot is functional and remains available on the existing `workers.dev` hostname. However, repeated CPU measurements show that the current full-stack Next.js/OpenNext SSR architecture does not satisfy the strict Cloudflare Workers Free 10 ms/request CPU budget. Therefore:

**Cloudflare Workers Free is NOT APPROVED as the full-stack SSR production runtime for the current architecture.**

This is a valid pilot outcome, not a pilot failure. The system keeps a working DEVELOPMENT proof while avoiding an unsafe production cutover or security trade-off.

## Workstream disposition

| Workstream | Handoff status | Operating decision |
| --- | --- | --- |
| ZC-1 Architecture baseline | COMPLETE | Zero recurring infrastructure cost remains a first-class requirement; paid upgrades require owner authorization. |
| ZC-2 Capacity monitoring | COMPLETE | Supabase capacity thresholds remain binding: NORMAL <300 MB; WARNING 300–350 MB; ARCHIVE_REQUIRED 350–400 MB; CRITICAL 400–450 MB; emergency before 450 MB. |
| ZC-3 Backup foundation | COMPLETE | Logical backup, encryption/checksum/read-back/restore-test controls established; scheduled backup workflow retained. |
| ZC-4 Archive foundation | COMPLETE FOR NON-DESTRUCTIVE FOUNDATION | Registry, integrity controls, synthetic packaging/reconstruction rehearsal established. No real-data prune/delete/purge is authorized. |
| ZC-5 Cloudflare pilot | COMPLETE | Build, local workerd, remote DEVELOPMENT runtime, auth/dashboard, analytics, CPU measurement, and zero-cost boundaries tested. |
| ZC-6 Production cutover decision | COMPLETE — NO-GO | No Cloudflare production cutover under current Workers Free CPU budget. |

## Current deployment position

### Cloudflare

- Worker: `kdkmp-development-pilot`
- Purpose: DEVELOPMENT / compatibility / diagnostic pilot only
- Host type: Cloudflare-provided `workers.dev`
- Latest authorized CPU-test Worker version: `d5c75ba1-78c6-4551-a6f6-e0da54865aa1`
- R2: not activated
- Paid account subscription observed after redeploy: 0
- Persistent binding types observed after redeploy: `assets,plain_text`
- Custom domain: not configured
- Production cutover: not performed
- Production data: not used

### Existing DEVELOPMENT path

Vercel DEVELOPMENT remains intact. The Cloudflare pilot did not authorize replacing or deleting the existing DEVELOPMENT path.

### Supabase DEVELOPMENT

Supabase DEVELOPMENT remains the hot operational database/auth environment for the current stage. Existing database capacity, backup, restore-test, RLS, audit, and archive safety controls remain binding.

## Cloudflare CPU decision evidence

The no-session Supabase proxy fast path preserved fail-closed authorization but did not reduce CPU sufficiently for a strict Workers Free production decision.

Two postdeploy samples both reported median CPU above the 10 ms/request Free-plan budget:

| Route | Postdeploy sample 1 P50 | Postdeploy sample 2 P50 |
| --- | ---: | ---: |
| `/api/health` | 10.245 ms | 11.152 ms |
| `/login` | 26.345 ms | 22.208 ms |
| `/` | 32.861 ms | 28.505 ms |
| `/dashboard` unauthenticated | 21.660 ms | 21.757 ms |

Both samples reported zero request errors and zero exceeded-resource requests in the measured windows. This is sufficient to keep the DEVELOPMENT pilot useful, but not sufficient to approve a Free-plan full-stack SSR production cutover.

Detailed evidence: `docs/operations/zc5j-cloudflare-free-cpu-outcome.md`.

## Security and authorization position

The following remain prohibited unless separately and explicitly authorized:

- Cloudflare R2 activation or credentials;
- any paid Cloudflare service or billing upgrade;
- custom-domain configuration or purchase;
- Cloudflare production cutover;
- production Supabase creation or production real-data onboarding;
- destructive archive pruning/deletion/purge;
- weakening JWT validation, RLS, RBAC, permission, access-context, or audit controls to reduce runtime cost;
- Worker redeploys based on the consumed ZC-5J authorization.

The one-time ZC-5J redeploy authorization was consumed. Both temporary redeploy executors and the authorization marker were removed from `main` through PR/CI/merge cleanup.

## Operating controls to retain

1. Continue Supabase capacity monitoring and enforce the existing threshold policy before capacity becomes critical.
2. Keep scheduled logical backups and read-back/restore verification operating; a generated backup is not considered valid until integrity/read-back and restore evidence are satisfactory.
3. Keep archive operation non-destructive until an eligible real accounting period, reconciliation/close conditions, package verification, recovery proof, and a separate owner authorization for any prune action exist.
4. Keep Cloudflare analytics workflows read-only. They do not authorize redeploy, storage activation, or billing changes.
5. Keep Cloudflare DEVELOPMENT and Vercel DEVELOPMENT logically separate from any future production decision.
6. Preserve branch → PR → CI → merge for repository changes and Database Migration CI for database migrations.
7. Re-evaluate hosting only after a material runtime/architecture change or a different zero-cost hosting option is ready for an equivalent compatibility/security test.

## Owner browser sanity checks

Two low-risk browser checks remain to finish the interactive pilot hygiene record. They do not change the Cloudflare CPU NO-GO decision:

### Check A — authenticated reload

1. Log in to the Cloudflare DEVELOPMENT dashboard.
2. Confirm the browser address remains on the Cloudflare `workers.dev` hostname.
3. Reload the dashboard page.
4. PASS if the authenticated dashboard remains available without an unexpected return to `/login`.

### Check B — logout termination

1. From the authenticated Cloudflare dashboard, use the normal logout action.
2. Confirm the application returns to the unauthenticated/login state.
3. Navigate directly to `/dashboard`.
4. PASS if the protected route redirects back to `/login` and authenticated dashboard content is no longer available.

A full long-lived token-expiry/refresh lifecycle remains unproven and is explicitly deferred because Cloudflare Workers Free is not being promoted to production.

## Reconsideration criteria for Cloudflare production

A future Cloudflare production pilot requires all of the following:

- a material change expected to lower SSR/auth CPU or a platform/runtime capability change;
- fresh review of current Cloudflare/OpenNext/Next.js compatibility and limits;
- fresh owner authorization for any remote redeploy or new resource;
- repeat build/size/local workerd/remote auth/fail-closed tests;
- repeat CPU measurements demonstrating an acceptable operating margin, not merely a single passing outlier;
- no weakening of security or governance controls;
- explicit production cutover authorization after the compatibility matrix passes.

## Handoff conclusion

The Zero-Cost workstream has produced the intended decision framework and safety controls:

- capacity is monitored;
- backups are controlled and verifiable;
- archive foundations are non-destructive and recoverability-oriented;
- Cloudflare was tested in parallel without replacing the existing DEVELOPMENT path;
- the Cloudflare Free production CPU constraint was measured rather than assumed;
- production cutover was correctly rejected when the measured gate did not pass;
- temporary one-shot deployment authority was removed after use.

After the two owner browser sanity checks are recorded, parent tracker #58 can be considered ready for closure as a completed pilot/decision workstream. Future application phases should continue independently from this infrastructure decision, while preserving the zero-cost and safety constraints above.
