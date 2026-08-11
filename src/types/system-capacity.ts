import type { SupabaseClient } from "@supabase/supabase-js";
import type { PosDatabase } from "./pos";

type TableShape<Row, Insert = Partial<Row>, Update = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: [];
};

export type ZeroCostCapacityPolicyRow = {
  id: string;
  policy_code: string;
  database_normal_mb: number;
  database_warning_mb: number;
  database_archive_required_mb: number;
  database_critical_mb: number;
  database_emergency_mb: number;
  supabase_egress_target_mb: number;
  cloudflare_dynamic_target_per_day: number;
  r2_storage_target_mb: number;
  status: string;
  effective_from: string;
  notes: string | null;
  created_at: string;
};

export type SystemCapacitySnapshotRow = {
  id: string;
  capacity_policy_id: string;
  captured_at: string;
  database_bytes: number;
  database_mb: number;
  capacity_state: string;
  archive_bytes: number;
  backup_status: string;
  archive_status: string;
  restore_test_status: string;
  source: string;
  notes: string | null;
  created_at: string;
};

export type SystemCapacityDatabase = Omit<PosDatabase, "public"> & {
  public: Omit<PosDatabase["public"], "Tables"> & {
    Tables: PosDatabase["public"]["Tables"] & {
      zero_cost_capacity_policies: TableShape<ZeroCostCapacityPolicyRow>;
      system_capacity_snapshots: TableShape<SystemCapacitySnapshotRow>;
    };
  };
};

export type SystemCapacityClient = SupabaseClient<SystemCapacityDatabase>;

export function asSystemCapacityClient(client: unknown): SystemCapacityClient {
  return client as SystemCapacityClient;
}
