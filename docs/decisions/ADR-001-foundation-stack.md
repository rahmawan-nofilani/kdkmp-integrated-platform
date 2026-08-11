# ADR-001 — Initial Foundation Stack

**Status:** Proposed  
**Date:** 2026-08-11

## Context

The project owner is not a software engineer and the initial implementation must minimize operational complexity without sacrificing a clean enterprise architecture.

## Decision

Use the following initial stack:

- GitHub for source control and architecture documentation
- Next.js + TypeScript for the application
- Supabase PostgreSQL for operational data
- Supabase Auth for authentication
- Supabase Storage for initial object/document storage
- Vercel for application hosting/deployment
- Modular Monolith as the initial application architecture

## Why

This reduces the number of infrastructure services required in the early stages, supports rapid controlled development, and keeps a clear path for later service extraction if scale, compliance, or integration complexity requires it.

## Consequences

- Bounded contexts must remain explicit even inside one codebase.
- Authorization must not rely only on UI or client logic.
- Database migrations and RLS policies become first-class project artifacts.
- External integrations remain adapter-based.
- Dedicated workers/services may be introduced later through separate ADRs.
