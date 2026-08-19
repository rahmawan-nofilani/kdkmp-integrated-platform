# Release 1 DEVELOPMENT — Live UAT Checkpoint

Date: 2026-08-19  
Repository: `rahmawan-nofilani/kdkmp-integrated-platform`  
Environment: **DEVELOPMENT only**  
Production cutover: **NOT AUTHORIZED**

This checkpoint records live evidence collected after the canonical Release-1 readiness pack was written. It does not replace `release1-uat-readiness.md`; it narrows what is executable now and prevents test evidence from being fabricated when a domain is intentionally inactive.

## Deployment / Gate 0

- Vercel DEVELOPMENT is deployed and `READY`.
- Canonical app alias responds healthy and identifies the runtime as DEVELOPMENT.
- Supabase target is `qdxybbcksjivcidsupbd`.
- Git auto-deploy has been restored to disabled after the deliberate milestone deployment.
- Provider configuration remains fail-closed / inactive.
- Gate 0: **PASS**.

## UAT actor inventory

Current active DEVELOPMENT actors:

- MANAGER: 1
- CASHIER: 1 (`UAT CASHIER`)
- FINANCE_OFFICER: 1 (`UAT FINANCE`)
- BOARD: 0
- SUPERVISOR: 0
- TELLER: 0

The first BOARD bootstrap has **not** been consumed. The latest bootstrap attempt failed at Supabase Auth email delivery with `email rate limit exceeded`; no BOARD profile was created.

Actor provisioning progress: **3 / 6 = 50%**.

## Gate 1 policy preflight

Read-only permission evidence remains aligned with intended segregation of duties:

- CASHIER has no `SALES_VOID`, `SALES_RETURN`, or privileged Accounting write permissions.
- FINANCE_OFFICER has `ACCOUNTING_DRAFT_CREATE`, but not validate/post/period-manage.
- MANAGER has Accounting validate/period-manage plus POS void/return, but no `ACCOUNTING_POST`.
- BOARD baseline has `ACCOUNTING_POST`, but no draft/validate/period-manage/POS reversal privileges.
- SUPERVISOR has no tested privileged write permission.

This is preflight evidence only. Gate 1 remains incomplete until real role-by-role login, route/scope, cross-scope, and negative-write scenarios are executed.

## Gate 2 POS CASH readiness

Current DEVELOPMENT fixture state:

- POS terminal: 1
- ACTIVE sales price entries: 3
- positive stock rows: 3
- Accounting event mappings: 1
- OPEN POS shifts: 0
- COMPLETED sales: 0

Interpretation: POS CASH has enough baseline terminal/catalog/price/stock/accounting configuration to begin human UAT once the CASHIER invitation is accepted and the actor can log in.

Gate 2 remains **UAT NOT EXECUTED**.

## Gate 3 POS reversal / return

The reversal and partial-return engines are implemented, but a completed synthetic CASH sale from Gate 2 is required as authoritative source evidence.

Gate 3 remains **DEPENDENT ON GATE 2**.

## Gate 4–5 Accounting readiness

Current DEVELOPMENT state:

- ACTIVE Accounting accounts: 20
- OPEN Accounting periods: 1
- journal entries: 0
- FINANCE_OFFICER actor: available
- MANAGER actor: available
- BOARD actor: not yet available

Interpretation: maker/checker infrastructure is ready, but full draft -> validate -> BOARD authorize/post and reversal/period-close UAT requires the BOARD actor and synthetic journal evidence.

Gate 4–5 remain **PARTIALLY READY / UAT NOT EXECUTED**.

## Gate 6 Inventory / Procurement scope correction

Inventory baseline is available:

- warehouses: 2
- inventory items: 3
- stock balance rows: 6
- suppliers: 2

Procurement transactional fixture state:

- purchase orders: 0
- purchase match results: 0

Control evidence also shows `PURCHASE_CREATE` / `PURCHASE_SUBMIT` / `PURCHASE_MATCH` mappings, but no active role mapping for `PURCHASE_APPROVE` was found and no active Procurement approval policy was found in the DEVELOPMENT data inspected for this checkpoint.

Therefore a full PR -> approval -> PO -> receiving -> match scenario must **not** be manufactured by direct inserts merely to make Gate 6 appear complete. Until a controlled approval/execution path is available, classify full procurement transaction execution as `BLOCKED_TEST_FIXTURE` / release-scope gap rather than weakening SoD.

Read-only inventory/supplier/scoped visibility cases may still proceed when the relevant UAT actors are available.

## Gate 7 Cooperative / Savings / Loan / Teller scope correction

Current DEVELOPMENT state:

- members: 2
- savings accounts: 0
- loan accounts: 0
- teller sessions: 0

All current DEMO Savings/Loan products are intentionally inactive:

- product status: `DRAFT`
- version status: `DRAFT`
- legal product type: not yet set
- Accounting mapping: `NOT_CONFIGURED`
- regulatory validation: `PENDING`
- `SAVINGS_LOANS` operating authorization: `PENDING_VALIDATION`

Therefore savings/loan monetary transactions must **not** be activated or faked for UAT. Gate 7 should execute only currently enabled read/scope/permission cases. Transactional teller/savings/loan cases are `DEFERRED` until the product, accounting, regulatory, and authorization gates are intentionally completed.

This is an intentional safety boundary, not a defect to bypass.

## Gate 8 Reconciliation / audit

- reconciliation runs: 0
- reconciliation exceptions: 0

Expected evidence should be generated from executed Gate 2–7 transactions rather than fabricated directly. Audit evidence already exists for controlled access-administration commands.

Gate 8 remains **DEPENDENT ON TRANSACTION UAT**.

## Gate 9 Browser / accessibility

Implementation-level accessibility/loading/reduced-motion work is already merged. Formal smoke evidence still requires a real browser session at desktop/mobile widths with keyboard/touch checks.

Gate 9 remains **HUMAN UAT PENDING**.

## Gate 10 provider boundary

Current implementation remains intentionally fail-closed:

- provider configs are not operationally activated;
- Xendit webhook requires server-side callback token, business ID, and service-role configuration before it processes provider events;
- invalid/missing provider configuration returns a fail-closed response;
- browser/manual cashier evidence is not accepted as proof of QRIS/BANK_TRANSFER payment.

Real provider E2E and commercial settlement remain separately blocked by credentials/commercial authorization.

## Current execution classification

- Gate 0: **PASS**
- Gate 1: **IN PROGRESS**
- Gate 2: **READY FOR CASHIER UAT**
- Gate 3: **DEPENDENT ON GATE 2**
- Gate 4: **PARTIALLY READY; BOARD REQUIRED**
- Gate 5: **PARTIALLY READY; BOARD + JOURNAL EVIDENCE REQUIRED**
- Gate 6: **INVENTORY READINESS AVAILABLE; FULL PROCUREMENT FLOW BLOCKED/UNPROVEN**
- Gate 7: **READ-ONLY/PERMISSION UAT ONLY; FINANCIAL TRANSACTIONS DEFERRED BY DESIGN**
- Gate 8: **DEPENDENT ON TRANSACTION EVIDENCE**
- Gate 9: **HUMAN BROWSER UAT PENDING**
- Gate 10: **FAIL-CLOSED READINESS; REAL PROVIDER E2E BLOCKED**

## Safety controls

- Do not write directly to `auth.users`.
- Do not manufacture authoritative financial/procurement history through ad-hoc inserts.
- Do not weaken RBAC, RLS, scope, SoD, provider verification, or audit controls to make a UAT case pass.
- Do not activate Savings/Loan products without the explicit legal/accounting/regulatory authorization chain.
- Do not activate real QRIS/BANK_TRANSFER or production data.
- Keep fixes branch -> PR -> CI -> merge and batch deployments to preserve Zero-Cost quota.
