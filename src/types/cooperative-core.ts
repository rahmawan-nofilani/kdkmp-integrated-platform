import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database as BaseDatabase, Json } from "./database";

type MemberRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  member_number: string | null;
  full_name: string;
  status: string;
  membership_date: string | null;
  termination_date: string | null;
  notes: string | null;
  created_by: string | null;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
};

type MemberStatusHistoryRow = {
  id: string;
  member_id: string;
  organization_id: string;
  organization_node_id: string;
  from_status: string | null;
  to_status: string;
  effective_at: string;
  reason: string | null;
  changed_by: string | null;
  created_at: string;
};

type MemberTransitionRow = {
  id: string;
  organization_id: string | null;
  from_status: string;
  to_status: string;
  enabled: boolean;
  requires_reason: boolean;
  policy_status: string;
  description: string | null;
  created_at: string;
  updated_at: string;
};

type GovernanceBodyRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  code: string;
  name: string;
  body_type: string;
  status: string;
  effective_from: string | null;
  effective_until: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

type GovernanceAssignmentRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  governance_body_id: string;
  governance_position_id: string;
  member_id: string | null;
  profile_id: string | null;
  person_name_snapshot: string;
  term_start: string | null;
  term_end: string | null;
  status: string;
  appointment_reference: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
};

type GeneralMeetingRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  code: string;
  title: string;
  meeting_type: string;
  period_year: number | null;
  status: string;
  scheduled_at: string | null;
  held_at: string | null;
  venue: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
};

type MeetingResolutionRow = {
  id: string;
  meeting_id: string;
  organization_id: string;
  organization_node_id: string;
  resolution_number: string | null;
  title: string;
  decision_text: string | null;
  status: string;
  decided_at: string | null;
  created_by: string | null;
  approved_by: string | null;
  created_at: string;
  updated_at: string;
};

type ShuPeriodRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  fiscal_year: number;
  shu_policy_version_id: string | null;
  status: string;
  calculation_snapshot: Json | null;
  notes: string | null;
  created_by: string | null;
  approved_by: string | null;
  created_at: string;
  updated_at: string;
  approved_at: string | null;
};

type TableShape<Row> = {
  Row: Row;
  Insert: Partial<Row>;
  Update: Partial<Row>;
  Relationships: [];
};

export type CooperativeDatabase = Omit<BaseDatabase, "public"> & {
  public: Omit<BaseDatabase["public"], "Tables" | "Functions"> & {
    Tables: BaseDatabase["public"]["Tables"] & {
      members: TableShape<MemberRow>;
      member_status_history: TableShape<MemberStatusHistoryRow>;
      member_status_transition_rules: TableShape<MemberTransitionRow>;
      governance_bodies: TableShape<GovernanceBodyRow>;
      governance_assignments: TableShape<GovernanceAssignmentRow>;
      general_meetings: TableShape<GeneralMeetingRow>;
      meeting_resolutions: TableShape<MeetingResolutionRow>;
      shu_periods: TableShape<ShuPeriodRow>;
    };
    Functions: BaseDatabase["public"]["Functions"] & {
      create_member: {
        Args: {
          p_full_name: string;
          p_member_number?: string;
          p_notes?: string;
          p_organization_node_id?: string;
        };
        Returns: string;
      };
      update_member_basic: {
        Args: {
          p_member_id: string;
          p_full_name: string;
          p_member_number?: string;
          p_notes?: string;
        };
        Returns: undefined;
      };
      change_member_status: {
        Args: {
          p_member_id: string;
          p_new_status: string;
          p_reason?: string;
        };
        Returns: undefined;
      };
    };
  };
};

export type CooperativeClient = SupabaseClient<CooperativeDatabase>;

export function asCooperativeClient(client: unknown): CooperativeClient {
  return client as CooperativeClient;
}
