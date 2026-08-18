# Release 1 — DEVELOPMENT UAT Readiness Pack

Date: 2026-08-18  
Repository: `rahmawan-nofilani/kdkmp-integrated-platform`  
Environment: **DEVELOPMENT only**  
Production cutover: **NOT AUTHORIZED**

## Purpose

This document is the single UAT execution plan for Release 1. It is designed to minimize zero-cost resource consumption by preparing all test cases before one deliberate DEVELOPMENT deployment. It does not authorize provider credentials, paid resources, production data, staging migration, or production cutover.

## Release boundary

### Ready for DEVELOPMENT UAT

- authentication, protected shell, RBAC, and hierarchical data scope;
- cooperative/member foundation;
- inventory and warehouse operational flows;
- procurement / receiving foundations;
- POS CASH cart, shift, sale completion, stock issue, accounting journal, cash movement, and receipt;
- full CASH void/reversal;
- controlled partial CASH return/refund;
- MANAGER-only `SALES_VOID` and `SALES_RETURN` baseline controls;
- Accounting manual journal maker/checker/BOARD poster workflow;
- Accounting manual reversal and controlled period close;
- Accounting multi-line journal editor and reconciliation drill-down;
- global interaction/loading accessibility feedback;
- provider-neutral non-cash confirmation/reconciliation backend foundation.

### Intentionally blocked from operational UAT

- real QRIS / BANK_TRANSFER completion through Xendit: credentials, business ID, callback token, provider config, fee/MDR terms, and accounting clearing mappings are not activated;
- production infrastructure and production data;
- Supabase region migration / staging cutover;
- optional offline payment confirmation, which is prohibited by design.

## UAT actor set

Use dedicated DEVELOPMENT test users. Do not reuse one profile for incompatible SoD roles.

| Actor | Primary role | UAT responsibility |
|---|---|---|
| UAT-MGR | MANAGER | operational approval, POS void/return, accounting validation, period soft-close |
| UAT-FIN | FINANCE_OFFICER | manual accounting draft/reversal, reconciliation review |
| UAT-BOARD | BOARD | accounting authorization/posting and hard-close |
| UAT-SUP | SUPERVISOR | read/review/audit negative-write verification |
| UAT-CASH | CASHIER | POS shift/cart/cash sale; must not receive SALES_VOID/SALES_RETURN |
| UAT-TELLER | TELLER or applicable teller role | teller/savings/loan transaction checks where enabled |

If a role has no active DEVELOPMENT profile yet, record the case as `BLOCKED_TEST_FIXTURE`; do not weaken RBAC to make testing easier.

## Evidence rule

Every executed case records:

- UAT case ID;
- actor/profile role;
- organization node/scope;
- timestamp;
- input/reference IDs with no secrets;
- expected result;
- actual result;
- PASS / FAIL / BLOCKED;
- screenshot only when useful for UI evidence;
- authoritative database/audit reference for financial state transitions;
- cleanup/rollback status for synthetic data.

Never store passwords, API keys, callback tokens, service-role keys, or full sensitive customer/member data in UAT evidence.

## Gate 0 — deployment and environment integrity

| ID | Scenario | Expected |
|---|---|---|
| UAT-0001 | Deploy one deliberate `main` milestone to Vercel DEVELOPMENT | READY deployment from intended main SHA; no production cutover |
| UAT-0002 | Verify application identifies DEVELOPMENT context | No UI/documentation claims true production |
| UAT-0003 | Verify Supabase target | Only project `qdxybbcksjivcidsupbd` is used |
| UAT-0004 | Verify migration history | Repository migrations expected for DEVELOPMENT are present; no history rewrite |
| UAT-0005 | Verify security advisors | No new critical finding introduced by release milestone |
| UAT-0006 | Verify provider state | Xendit/provider config remains inactive until credential authorization |

## Gate 1 — authentication, RBAC, and scope

| ID | Actor | Scenario | Expected |
|---|---|---|---|
| UAT-1001 | each role | Login and protected dashboard access | Active role enters only permitted workspace |
| UAT-1002 | scoped actor | Read data inside assigned organization scope | Allowed |
| UAT-1003 | scoped actor | Attempt cross-scope record access | Denied / no data leakage |
| UAT-1004 | CASHIER | Attempt `SALES_VOID` | Denied |
| UAT-1005 | CASHIER | Attempt `SALES_RETURN` | Denied |
| UAT-1006 | SUPERVISOR | Attempt Accounting draft/validate/post/close write | Denied |
| UAT-1007 | MANAGER | Attempt `ACCOUNTING_POST` | Denied |
| UAT-1008 | FINANCE_OFFICER | Attempt validate/post own journal | Denied |

## Gate 2 — POS CASH happy path

| ID | Scenario | Expected authoritative state |
|---|---|---|
| UAT-2001 | Cashier opens/uses owned active shift | One valid OPEN shift for actor/terminal |
| UAT-2002 | Search/scan catalog and add item | Scoped active catalog, authoritative price/stock snapshot |
| UAT-2003 | Update quantity/cart | Server-authoritative totals; idempotent command behavior |
| UAT-2004 | Optional member/customer association | Only permitted member fields exposed |
| UAT-2005 | Complete CASH sale | Payment settled + sale COMPLETED + SALE_ISSUE + POSTED journal + cash movement + receipt |
| UAT-2006 | Retry completion command | No duplicate sale/payment/journal/stock/cash receipt artifacts |
| UAT-2007 | Validate receipt | Receipt references authoritative completed sale |

## Gate 3 — POS reversal and return

| ID | Actor | Scenario | Expected |
|---|---|---|---|
| UAT-3001 | MANAGER | Full void eligible completed CASH sale | Append-only reversal/refund; source history retained |
| UAT-3002 | CASHIER | Full void | Denied |
| UAT-3003 | MANAGER | Partial item return | Derived amount/qty, RETURN_IN, refund/accounting/cash-refund evidence |
| UAT-3004 | MANAGER | Repeated partial return within remaining qty | Allowed |
| UAT-3005 | MANAGER | Return beyond original cumulative qty | Denied |
| UAT-3006 | MANAGER | Full void after partial return | Denied |
| UAT-3007 | MANAGER | Return final remaining quantity | Sale reaches RETURNED according to controlled workflow |

## Gate 4 — Accounting maker/checker/poster

| ID | Actor | Scenario | Expected |
|---|---|---|---|
| UAT-4001 | FINANCE_OFFICER | Create 2-line DRAFT | DRAFT only; no GL posting |
| UAT-4002 | FINANCE_OFFICER | Create balanced multi-line DRAFT | Up to 20 valid lines; DRAFT only |
| UAT-4003 | FINANCE_OFFICER | Submit unbalanced/invalid lines | Client aid + authoritative server/database rejection |
| UAT-4004 | same maker | Validate own draft | Denied maker-checker |
| UAT-4005 | MANAGER | Validate Finance draft | VALIDATED + BOARD approval request |
| UAT-4006 | MANAGER | Post validated journal | Denied |
| UAT-4007 | BOARD | Authorize without conflict declaration | Denied |
| UAT-4008 | BOARD | Authorize + post valid journal | POSTED, balanced, immutable |
| UAT-4009 | different BOARD actor | Post authorization created by other BOARD actor | Denied if actor-binding requires same authorizer |

## Gate 5 — Accounting reversal and period close

| ID | Actor | Scenario | Expected |
|---|---|---|---|
| UAT-5001 | FINANCE_OFFICER | Create reversal from POSTED MANUAL journal | New reversal DRAFT; source remains POSTED immutable |
| UAT-5002 | FINANCE_OFFICER | Attempt reversal of non-manual domain journal | Denied; domain engine required |
| UAT-5003 | MANAGER | Validate reversal | VALIDATED |
| UAT-5004 | BOARD | Authorize/post reversal | Mirrored debit/credit; append-only |
| UAT-5005 | any | Duplicate active reversal | Denied |
| UAT-5006 | MANAGER | Soft-close period before end date | Denied |
| UAT-5007 | MANAGER | Soft-close ended clean period | SOFT_CLOSED |
| UAT-5008 | MANAGER | Hard-close period | Denied |
| UAT-5009 | BOARD distinct actor | Hard-close clean SOFT_CLOSED period with conflict declaration | HARD_CLOSED |
| UAT-5010 | close actor | Close with DRAFT/VALIDATED journal, open approval, reconciliation exception, or imbalance | Denied |

## Gate 6 — Inventory and procurement

Execute with existing DEVELOPMENT fixtures and only within actor scope.

| ID | Scenario | Expected |
|---|---|---|
| UAT-6001 | Inventory item/warehouse scoped read | Correct stock visibility; no cross-scope leakage |
| UAT-6002 | Receiving flow | Receipt increases authoritative inventory according to source document |
| UAT-6003 | PO / receiving / three-way-match happy path | References remain linked and auditable |
| UAT-6004 | Quantity/amount mismatch | Exception/control state rather than silent posting |
| UAT-6005 | POS sale after receiving | Stock reflects both receipt and sale issue without direct history mutation |

## Gate 7 — Cooperative financial products / teller

These cases validate currently enabled DEVELOPMENT foundations; mark unsupported operations as `DEFERRED` rather than inventing behavior.

| ID | Scenario | Expected |
|---|---|---|
| UAT-7001 | Member access from permitted role | Correct scoped member identity/data |
| UAT-7002 | Savings/loan product configuration read | Correct active configuration |
| UAT-7003 | Teller session / permitted transaction flow | Permission + session controls enforced |
| UAT-7004 | Financial transaction retry | No duplicate authoritative ledger effect |
| UAT-7005 | Unauthorized teller/finance action | Denied and auditable |

## Gate 8 — reconciliation and audit evidence

| ID | Scenario | Expected |
|---|---|---|
| UAT-8001 | Open reconciliation drill-down | Scoped run summary + exception register only |
| UAT-8002 | Reconciliation with difference/exception | Visible and blocks period close where designed |
| UAT-8003 | Audit trail for POS financial command | Actor/action/source IDs recorded |
| UAT-8004 | Audit trail for Accounting draft→validate→post | Distinct actors and transition evidence recorded |
| UAT-8005 | Sensitive secret check | No credentials/secrets in browser-visible evidence or audit payloads |

## Gate 9 — responsive/accessibility/browser smoke

At minimum execute desktop and mobile-width checks in a modern Chromium browser; add another browser when available without paid tooling.

| ID | Scenario | Expected |
|---|---|---|
| UAT-9001 | Keyboard navigation | Visible focus ring and logical navigation |
| UAT-9002 | Button/link pressed feedback | Clear but subtle active state |
| UAT-9003 | Mobile navigation/touch | Large usable touch targets; no accidental double-tap behavior |
| UAT-9004 | Route transition | Loading feedback shown when route/data transition is non-instant |
| UAT-9005 | Reduced motion | Meaningful motion suppressed under `prefers-reduced-motion: reduce` |
| UAT-9006 | Wide tables on mobile | Horizontal scroll contained; page remains usable |

## Gate 10 — non-cash provider boundary

These are readiness checks only until explicit credential authorization.

| ID | Scenario | Current expected result |
|---|---|---|
| UAT-10001 | Browser/cashier marks QRIS/BANK_TRANSFER as paid manually | Impossible / denied |
| UAT-10002 | Unverified webhook/callback | Denied |
| UAT-10003 | Inactive/unvalidated provider config | Fail closed |
| UAT-10004 | Real Xendit QRIS/VA success | `BLOCKED_PROVIDER_CREDENTIAL` |
| UAT-10005 | Settlement and MDR/fee reconciliation against real provider terms | `BLOCKED_PROVIDER_COMMERCIAL` |

## Severity and release decision

- **P0**: financial duplication, unauthorized posting/payment, cross-scope leak, accounting imbalance, destructive history mutation. Any P0 = NO-GO.
- **P1**: core operational path unavailable or incorrect authoritative state. Any unresolved P1 = NO-GO.
- **P2**: significant workflow/UX issue with safe workaround. Owner decision required.
- **P3**: cosmetic/non-blocking issue. May defer with issue reference.

Release-1 DEVELOPMENT UAT is considered complete only when all READY gates are executed, P0/P1 are zero, synthetic cleanup is verified, and blocked provider/infrastructure items are explicitly separated from application defects.

## Zero-cost execution plan

1. Freeze a tested `main` milestone SHA.
2. Verify all relevant GitHub Actions are green.
3. Perform **one deliberate Vercel DEVELOPMENT deployment** when explicitly authorized.
4. Create/verify dedicated UAT users and scoped fixtures in DEVELOPMENT only.
5. Execute Gates 0–9 in one milestone session; record evidence.
6. Keep Gate 10 fail-closed until Xendit credential/commercial authorization.
7. Fix defects branch → PR → CI → merge; batch fixes before the next deliberate deployment when practical.
8. After UAT passes, evaluate Issue #19 staging/region plan separately.
9. Production readiness/cutover remains a separate explicit authorization gate.

## Current go/no-go snapshot

- Core repo readiness for UAT preparation: **GO**.
- Deliberate DEVELOPMENT deployment: **NOT YET EXECUTED IN THIS CHECKPOINT**.
- Real provider E2E: **NO-GO until credentials/commercial terms authorized**.
- Production: **NO-GO / NOT AUTHORIZED**.
