import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database as BaseDatabase, Json } from "./database";

type TableShape<Row> = { Row: Row; Insert: Partial<Row>; Update: Partial<Row>; Relationships: [] };

type ApprovalPolicyRow = { id:string; organization_id:string; organization_node_id:string; code:string; name:string; domain:string; transaction_type:string; status:string; notes:string|null; created_at:string; updated_at:string };
type ApprovalPolicyVersionRow = { id:string; approval_policy_id:string; organization_id:string; organization_node_id:string; version_no:number; condition_config:Json; status:string; effective_from:string|null; effective_until:string|null; created_by:string|null; approved_by:string|null; approved_at:string|null; created_at:string };
type ApprovalPolicyStepRow = { id:string; approval_policy_version_id:string; organization_id:string; organization_node_id:string; step_no:number; step_name:string; required_permission_code:string; min_approvers:number; quorum_rule:string; prohibit_requester_approval:boolean; prohibit_previous_step_actor:boolean; require_conflict_declaration:boolean; allow_delegation:boolean; sla_minutes:number|null; escalation_config:Json; created_at:string };
type ApprovalRequestRow = { id:string; organization_id:string; organization_node_id:string; approval_policy_version_id:string; source_domain:string; source_entity_type:string; source_entity_id:string|null; source_reference:string|null; correlation_id:string|null; requested_by:string; requested_at:string; request_snapshot:Json; policy_snapshot:Json; status:string; current_step_no:number|null; completed_at:string|null };
type SodRuleRow = { id:string; organization_id:string; organization_node_id:string; code:string; name:string; domain:string; transaction_type:string|null; rule_type:string; subject_permission_code:string|null; conflicting_permission_code:string|null; condition_config:Json; status:string; effective_from:string|null; effective_until:string|null; notes:string|null; created_at:string };
type ApprovalDelegationRow = { id:string; organization_id:string; organization_node_id:string; delegator_profile_id:string; delegate_profile_id:string; permission_code:string; valid_from:string; valid_until:string; status:string; reason:string|null; created_by:string|null; created_at:string };

export type ApprovalDatabase = Omit<BaseDatabase,"public"> & { public: Omit<BaseDatabase["public"],"Tables"> & { Tables: BaseDatabase["public"]["Tables"] & {
  approval_policies: TableShape<ApprovalPolicyRow>;
  approval_policy_versions: TableShape<ApprovalPolicyVersionRow>;
  approval_policy_steps: TableShape<ApprovalPolicyStepRow>;
  approval_requests: TableShape<ApprovalRequestRow>;
  approval_delegations: TableShape<ApprovalDelegationRow>;
  sod_rules: TableShape<SodRuleRow>;
} } };

export type ApprovalClient = SupabaseClient<ApprovalDatabase>;
export function asApprovalClient(client: unknown): ApprovalClient { return client as ApprovalClient; }
