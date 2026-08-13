-- LOGISTICS ANON SELECT HARDENING REVIEW DRAFT ONLY
--
-- THIS FILE IS NOT A SUPABASE MIGRATION AND MUST NOT BE APPLIED DIRECTLY.
-- It is the reviewed SQL contract for the pinned Supabase CLI generator proof.
--
-- Read-only forensics against DEVELOPMENT proved that the logistics/fleet schema
-- matches a clean repository replay except for exactly ten unexpected SELECT
-- grants held by the anon role. This migration removes only that known drift.
--
-- Safety invariants:
--   * privilege hardening only; no table/data mutation;
--   * no DELETE/prune/purge/archive execution;
--   * no migration-history repair;
--   * no R2, paid storage, or billing change;
--   * authenticated grants and RLS policies are unchanged.

revoke select on
  public.fleet_vehicles,
  public.logistics_route_trips,
  public.logistics_shipments,
  public.logistics_route_trip_stops,
  public.logistics_delivery_events,
  public.logistics_pod_evidence,
  public.logistics_delivery_exceptions,
  public.fleet_odometer_entries,
  public.fleet_maintenance_records,
  public.logistics_status_transition_rules
from anon;
