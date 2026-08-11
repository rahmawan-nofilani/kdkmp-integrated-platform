# Phase 1 Foundation Status

Status: **IN PROGRESS**

## Completed
- Architecture Baseline merged to `main`.
- Supabase development database identified and used as DEVELOPMENT only.
- Identity/organization foundation migration applied.
- RLS enabled on Phase 1 public tables.
- Baseline role catalog created.
- Baseline permission catalog created.
- Initial role-permission assignments created.
- Regulatory authorization table created with `PENDING_VALIDATION` support.
- Audit log table created as append-only from normal application flows.
- Migration SQL stored in GitHub.
- `.gitignore` and `.env.example` added.

## Current database baseline
- 13 roles
- 50 permissions
- 90 role-permission mappings

## Security posture
- Default deny is used for tables that do not yet have an approved access policy.
- RLS is enabled on all Phase 1 public tables.
- `profiles` currently allows authenticated users to read/update their own profile record only.
- `roles` and `permissions` are readable to authenticated users.
- No normal frontend policy exists to update/delete audit logs.
- Sensitive management operations will be implemented server-side and must validate permission + scope + workflow rules.

## Not yet implemented
- Application package/bootstrap files
- Supabase auth UI
- Manager bootstrap/provisioning flow
- Login/logout/session handling
- Organization administration UI
- User management UI
- Role/permission administration UI
- Scope assignment UI
- Dashboard shell
- Automated RBAC tests
- Vercel deployment

## Regulatory note
All final legal/regulatory values remain **DRAFT / PENDING LEGAL VALIDATION** until official source documents are supplied and validated.
