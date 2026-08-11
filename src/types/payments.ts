import type { SupabaseClient } from "@supabase/supabase-js";
import type { FinancialServicesDatabase } from "./financial-services";
import type { Json } from "./database";

type TableShape<Row> = { Row: Row; Insert: Partial<Row>; Update: Partial<Row>; Relationships: [] };

type ProviderConfigRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string|null; code:string; provider_type:string; provider_name:string; supported_channels:string[]; config_status:string; status:string; secret_storage_reference:string|null; notes:string|null; created_at:string; updated_at:string };
type TellerSessionRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; teller_profile_id:string; session_number:string; business_date:string; opening_cash:number; expected_closing_cash:number|null; actual_closing_cash:number|null; variance_amount:number|null; status:string; opened_at:string|null; closed_at:string|null; opened_by:string|null; closed_by:string|null; notes:string|null; created_at:string; updated_at:string };
type PaymentIntentRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string|null; intent_number:string; business_purpose:string; source_domain:string; source_entity_type:string|null; source_entity_id:string|null; source_reference:string|null; payer_member_id:string|null; payee_member_id:string|null; amount:number; currency:string; status:string; idempotency_key:string|null; approval_request_id:string|null; expires_at:string|null; confirmed_at:string|null; settled_at:string|null; created_by:string|null; created_at:string; updated_at:string };
type PaymentAttemptRow = { id:string; payment_intent_id:string; organization_id:string; organization_node_id:string; organization_unit_id:string|null; provider_config_id:string|null; teller_session_id:string|null; attempt_no:number; channel:string; amount:number; currency:string; status:string; provider_reference:string|null; merchant_reference:string|null; failure_code:string|null; failure_message:string|null; created_at:string; confirmed_at:string|null; settled_at:string|null };
type PaymentEventRow = { id:string; organization_id:string; organization_node_id:string; provider_config_id:string|null; payment_attempt_id:string|null; external_event_id:string; event_type:string; received_at:string; payload_hash:string; sanitized_metadata:Json; signature_validation_status:string; processing_status:string; processed_at:string|null; error_message:string|null };
type SettlementBatchRow = { id:string; organization_id:string; organization_node_id:string; provider_config_id:string; settlement_reference:string; settlement_date:string; currency:string; gross_amount:number; fee_amount:number; net_amount:number; status:string; received_at:string; reconciled_at:string|null; notes:string|null };
type CashMovementRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; teller_session_id:string; payment_intent_id:string|null; payment_attempt_id:string|null; movement_type:string; direction:string; amount:number; currency:string; receipt_number:string|null; reason:string|null; approval_request_id:string|null; accounting_status:string; journal_entry_id:string|null; reversal_of_movement_id:string|null; occurred_at:string; created_by:string|null; created_at:string };

export type PaymentDatabase = Omit<FinancialServicesDatabase,"public"> & { public: Omit<FinancialServicesDatabase["public"],"Tables"> & { Tables: FinancialServicesDatabase["public"]["Tables"] & {
  payment_provider_configs: TableShape<ProviderConfigRow>;
  teller_sessions: TableShape<TellerSessionRow>;
  payment_intents: TableShape<PaymentIntentRow>;
  payment_attempts: TableShape<PaymentAttemptRow>;
  payment_external_events: TableShape<PaymentEventRow>;
  payment_settlement_batches: TableShape<SettlementBatchRow>;
  cash_movements: TableShape<CashMovementRow>;
} } };

export type PaymentClient = SupabaseClient<PaymentDatabase>;
export function asPaymentClient(client: unknown): PaymentClient { return client as PaymentClient; }
