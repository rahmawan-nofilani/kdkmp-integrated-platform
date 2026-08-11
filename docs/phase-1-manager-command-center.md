# Phase 1 — Manager Command Center

Status: IMPLEMENTATION IN PROGRESS

This increment turns the Phase 1 shell into a scoped Manager command center using live DEVELOPMENT data.

Planned capabilities:
- organization summary from the authenticated user's active organization;
- organization hierarchy and unit viewer constrained by RLS/data scope;
- active/pending user counts;
- enabled module and pending authorization counts;
- User & Access list constrained by `USER_VIEW`;
- no fabricated commercial KPI values;
- no production data.

Security rules:
- grants and RLS are configured together;
- organization data is limited to the caller's active organization and assigned scope;
- profile/user lists require `USER_VIEW`;
- cross-organization access is fail-closed;
- no service-role key is introduced into the web application.
