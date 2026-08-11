import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { asApprovalClient } from "@/types/approval";

export const dynamic = "force-dynamic";

export default async function ApprovalsPage() {
  await requirePermission("APPROVAL_VIEW");
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  const db = asApprovalClient(supabase);
  const organizationId = profile.organization_id;

  const [policiesResult, versionsResult, stepsResult, requestsResult, sodResult, delegationsResult] = await Promise.all([
    organizationId ? db.from("approval_policies").select("id,code,name,domain,transaction_type,status,notes").eq("organization_id", organizationId).order("domain").order("code") : Promise.resolve({ data: [], error: null }),
    organizationId ? db.from("approval_policy_versions").select("id,approval_policy_id,version_no,status,effective_from,effective_until").eq("organization_id", organizationId).order("version_no", { ascending: false }) : Promise.resolve({ data: [], error: null }),
    organizationId ? db.from("approval_policy_steps").select("id,approval_policy_version_id,step_no,step_name,required_permission_code,min_approvers,quorum_rule,prohibit_requester_approval,prohibit_previous_step_actor,require_conflict_declaration,allow_delegation,sla_minutes").eq("organization_id", organizationId).order("step_no") : Promise.resolve({ data: [], error: null }),
    organizationId ? db.from("approval_requests").select("id,source_domain,source_entity_type,source_reference,status,current_step_no,requested_at").eq("organization_id", organizationId).order("requested_at", { ascending: false }).limit(30) : Promise.resolve({ data: [], error: null }),
    organizationId ? db.from("sod_rules").select("id,code,name,domain,transaction_type,rule_type,subject_permission_code,conflicting_permission_code,status,notes").eq("organization_id", organizationId).order("domain").order("code") : Promise.resolve({ data: [], error: null }),
    organizationId ? db.from("approval_delegations").select("id,permission_code,valid_from,valid_until,status,reason").eq("organization_id", organizationId).order("valid_from", { ascending: false }).limit(20) : Promise.resolve({ data: [], error: null }),
  ]);

  const policies = policiesResult.data ?? [];
  const versions = versionsResult.data ?? [];
  const steps = stepsResult.data ?? [];
  const requests = requestsResult.data ?? [];
  const sodRules = sodResult.data ?? [];
  const delegations = delegationsResult.data ?? [];
  const activePolicies = policies.filter((policy) => policy.status === "ACTIVE");
  const activeSod = sodRules.filter((rule) => rule.status === "ACTIVE");
  const pendingRequests = requests.filter((request) => ["PENDING", "IN_REVIEW"].includes(request.status));

  const canDraftPolicy = permissionCodes.includes("APPROVAL_POLICY_DRAFT");
  const canActivatePolicy = permissionCodes.includes("APPROVAL_POLICY_ACTIVATE");
  const canManageDelegation = permissionCodes.includes("APPROVAL_DELEGATION_MANAGE");
  const canManageSod = permissionCodes.includes("SOD_POLICY_MANAGE");
  const canDecide = permissionCodes.includes("APPROVAL_DECIDE");

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Governance Control</p>
          <h1>Approval & Segregation of Duties</h1>
          <p>
            Mesin persetujuan lintas modul. Policy DEVELOPMENT masih DRAFT dan belum boleh mengendalikan transaksi sampai governance review selesai.
            Nominal, risk band, quorum, delegasi, serta conflict rules disimpan sebagai konfigurasi versioned—bukan hardcoded di halaman.
          </p>
        </div>
        <span className="status-pill">CONTROL FOUNDATION</span>
      </section>

      <section className="metric-grid">
        <article className="metric-card"><div className="metric-label">Policy</div><div className="metric-value">{policies.length}</div><div className="metric-note">{activePolicies.length} ACTIVE · sisanya belum mengikat transaksi.</div></article>
        <article className="metric-card"><div className="metric-label">Workflow Steps</div><div className="metric-value">{steps.length}</div><div className="metric-note">Snapshot step akan melekat ke approval request.</div></article>
        <article className="metric-card"><div className="metric-label">SoD Rules</div><div className="metric-value">{sodRules.length}</div><div className="metric-note">{activeSod.length} ACTIVE · rule DEMO masih DRAFT.</div></article>
        <article className="metric-card"><div className="metric-label">Pending Requests</div><div className="metric-value">{pendingRequests.length}</div><div className="metric-note">Belum ada request transaksi karena modul write belum diaktifkan.</div></article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Kewenangan Akun Ini</h3>
          <p className="panel-subtitle">Permission efektif tetap menjadi gate; role saja tidak cukup.</p>
          <div className="check-list">
            <div className="check-item"><span>Lihat approval</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Draft policy</span><span className={`check-state ${canDraftPolicy ? "" : "pending"}`}>{canDraftPolicy ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Aktifkan policy</span><span className={`check-state ${canActivatePolicy ? "" : "pending"}`}>{canActivatePolicy ? "ALLOWED" : "BLOCKED"}</span></div>
            <div className="check-item"><span>Putuskan approval</span><span className={`check-state ${canDecide ? "" : "pending"}`}>{canDecide ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Kelola delegasi</span><span className={`check-state ${canManageDelegation ? "" : "pending"}`}>{canManageDelegation ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Kelola SoD</span><span className={`check-state ${canManageSod ? "" : "pending"}`}>{canManageSod ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Control Gate</h3>
          <p className="panel-subtitle">Kenapa workflow belum diaktifkan.</p>
          <div className="check-list">
            <div className="check-item"><span>Policy version model</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Step snapshot model</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Decision evidence model</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>SoD configuration</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Business thresholds</span><span className="check-state pending">PENDING</span></div>
            <div className="check-item"><span>Policy activation authority</span><span className="check-state pending">PENDING</span></div>
          </div>
        </article>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Approval Policy Templates</h3><p className="panel-subtitle">Semua template DEMO tetap DRAFT. Tidak ada nominal threshold yang dianggap aturan resmi.</p></div></div>
        <div className="data-table-wrap">
          <table className="data-table">
            <thead><tr><th>Policy</th><th>Domain</th><th>Transaction</th><th>Version</th><th>Steps</th><th>Status</th></tr></thead>
            <tbody>{policies.map((policy) => {
              const version = versions.find((item) => item.approval_policy_id === policy.id);
              const policySteps = version ? steps.filter((step) => step.approval_policy_version_id === version.id) : [];
              return <tr key={policy.id}><td><strong>{policy.name}</strong><small className="item-subtext">{policy.code}</small></td><td>{policy.domain}</td><td>{policy.transaction_type}</td><td>{version ? `v${version.version_no} · ${version.status}` : "—"}</td><td>{policySteps.length ? policySteps.map((step) => `${step.step_no}. ${step.step_name} [${step.required_permission_code}]`).join(" → ") : "—"}</td><td><span className="table-status">{policy.status}</span></td></tr>;
            })}</tbody>
          </table>
        </div>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Segregation of Duties</h3><p className="panel-subtitle">Rule konflik aktor disiapkan sebelum transaksi pinjaman/pembayaran/posting dibuka.</p></div></div>
        <div className="data-table-wrap">
          <table className="data-table">
            <thead><tr><th>Rule</th><th>Domain</th><th>Type</th><th>Permission A</th><th>Permission B</th><th>Status</th></tr></thead>
            <tbody>{sodRules.map((rule) => <tr key={rule.id}><td><strong>{rule.name}</strong><small className="item-subtext">{rule.rule_type}</small></td><td>{rule.domain}</td><td>{rule.transaction_type ?? "—"}</td><td>{rule.subject_permission_code ?? "—"}</td><td>{rule.conflicting_permission_code ?? "—"}</td><td><span className="table-status">{rule.status}</span></td></tr>)}</tbody>
          </table>
        </div>
      </section>

      <section className="dashboard-grid">
        <article className="panel"><h3>Approval Requests</h3><p className="panel-subtitle">Nanti terisi dari transaksi domain, bukan dibuat manual dari dashboard ini.</p>{requests.length ? <div className="check-list">{requests.map((request) => <div className="check-item" key={request.id}><span>{request.source_domain} · {request.source_entity_type}<small className="item-subtext">{request.source_reference ?? request.id}</small></span><span className="check-state pending">{request.status}</span></div>)}</div> : <div className="empty-state">Belum ada approval request. Kondisi ini disengaja.</div>}</article>
        <article className="panel"><h3>Delegation</h3><p className="panel-subtitle">Delegasi tidak berarti meminjam akun/password; delegasi harus tercatat dengan masa berlaku.</p>{delegations.length ? <div className="check-list">{delegations.map((delegation) => <div className="check-item" key={delegation.id}><span>{delegation.permission_code}<small className="item-subtext">{delegation.valid_from} — {delegation.valid_until}</small></span><span className="check-state pending">{delegation.status}</span></div>)}</div> : <div className="empty-state">Belum ada delegation record.</div>}</article>
      </section>
    </>
  );
}
