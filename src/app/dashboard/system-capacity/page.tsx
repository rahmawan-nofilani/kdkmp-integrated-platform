import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { asSystemCapacityClient } from "@/types/system-capacity";

export const dynamic = "force-dynamic";

function formatMb(value: number) {
  return new Intl.NumberFormat("id-ID", { maximumFractionDigits: 2 }).format(value);
}

function formatDateTime(value: string | null | undefined) {
  if (!value) return "Belum ada";
  return new Intl.DateTimeFormat("id-ID", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Jakarta",
  }).format(new Date(value));
}

function stateClass(state: string) {
  return state === "NORMAL" || state === "VERIFIED" || state === "PASSED" ? "" : "pending";
}

export default async function SystemCapacityPage() {
  await requirePermission("SYSTEM_CAPACITY_VIEW");
  const { profile, supabase } = await requireAccessContext();
  const db = asSystemCapacityClient(supabase);
  const organizationId = profile.organization_id;
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

  const [policyResult, snapshotResult, backupResult, restoreResult, membersResult, activeMembersResult, sales30dResult] = await Promise.all([
    db
      .from("zero_cost_capacity_policies")
      .select("id,policy_code,database_normal_mb,database_warning_mb,database_archive_required_mb,database_critical_mb,database_emergency_mb,supabase_egress_target_mb,cloudflare_dynamic_target_per_day,r2_storage_target_mb,status,effective_from,notes,created_at")
      .eq("status", "ACTIVE")
      .order("effective_from", { ascending: false })
      .limit(1)
      .maybeSingle(),
    db
      .from("system_capacity_snapshots")
      .select("id,capacity_policy_id,captured_at,database_bytes,database_mb,capacity_state,archive_bytes,backup_status,archive_status,restore_test_status,source,notes,created_at")
      .order("captured_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    db
      .from("system_backup_runs")
      .select("id,backup_run_number,backup_type,retention_class,status,storage_provider,object_key,encrypted,size_bytes,sha256,manifest,source,started_at,uploaded_at,verified_at,completed_at,error_summary,created_at")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    db
      .from("system_restore_tests")
      .select("id,backup_run_id,restore_test_number,status,target_type,row_count_checks,integrity_checks,started_at,completed_at,duration_seconds,notes,error_summary,created_at")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    organizationId
      ? db.from("members").select("id", { count: "exact", head: true }).eq("organization_id", organizationId)
      : Promise.resolve({ count: 0, error: null }),
    organizationId
      ? db.from("members").select("id", { count: "exact", head: true }).eq("organization_id", organizationId).eq("status", "ACTIVE")
      : Promise.resolve({ count: 0, error: null }),
    organizationId
      ? db.from("sales_transactions").select("id", { count: "exact", head: true }).eq("organization_id", organizationId).eq("sale_type", "POS").gte("created_at", thirtyDaysAgo)
      : Promise.resolve({ count: 0, error: null }),
  ]);

  const policy = policyResult.data;
  const snapshot = snapshotResult.data;
  const latestBackup = backupResult.data;
  const latestRestore = restoreResult.data;
  const memberCount = membersResult.count ?? 0;
  const activeMemberCount = activeMembersResult.count ?? 0;
  const sales30d = sales30dResult.count ?? 0;
  const currentMb = Number(snapshot?.database_mb ?? 0);
  const safeCeilingMb = Number(policy?.database_emergency_mb ?? 475);
  const usagePercent = safeCeilingMb > 0 ? Math.min((currentMb / safeCeilingMb) * 100, 100) : 0;
  const backupState = latestBackup?.status ?? snapshot?.backup_status ?? "NOT_CONFIGURED";
  const restoreState = latestRestore?.status ?? snapshot?.restore_test_status ?? "NOT_TESTED";

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Zero-Cost Mode</p>
          <h1>Kapasitas Sistem</h1>
          <p>
            Monitor read-only untuk menjaga aplikasi tetap berada di jalur biaya infrastruktur Rp0. Halaman ini belum
            dapat menghapus, mengarsipkan, atau memindahkan data secara otomatis.
          </p>
        </div>
        <span className="status-pill">{snapshot?.capacity_state ?? "NO SNAPSHOT"}</span>
      </section>

      <section className="metric-grid">
        <article className="metric-card">
          <div className="metric-label">Database</div>
          <div className="metric-value">{formatMb(currentMb)} MB</div>
          <div className="metric-note">{usagePercent.toFixed(1)}% dari safety ceiling {formatMb(safeCeilingMb)} MB.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Anggota Scope Anda</div>
          <div className="metric-value">{memberCount}</div>
          <div className="metric-note">{activeMemberCount} anggota berstatus ACTIVE.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">POS 30 Hari</div>
          <div className="metric-value">{sales30d}</div>
          <div className="metric-note">Dihitung dari transaksi nyata pada scope organisasi Anda.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Snapshot Terakhir</div>
          <div className="metric-value" style={{ fontSize: "1.05rem" }}>{formatDateTime(snapshot?.captured_at)}</div>
          <div className="metric-note">Sumber: {snapshot?.source ?? "belum tersedia"}.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Traffic Light Database</h3>
              <p className="panel-subtitle">Batas internal dibuat lebih konservatif daripada hard limit provider.</p>
            </div>
          </div>
          {policy ? (
            <div className="check-list">
              <div className="check-item"><span>Normal</span><span className="check-state">&lt; {policy.database_normal_mb} MB</span></div>
              <div className="check-item"><span>Warning</span><span className="check-state pending">{policy.database_normal_mb}–{policy.database_warning_mb} MB</span></div>
              <div className="check-item"><span>Archive Required</span><span className="check-state pending">{policy.database_warning_mb}–{policy.database_archive_required_mb} MB</span></div>
              <div className="check-item"><span>Critical</span><span className="check-state pending">{policy.database_archive_required_mb}–{policy.database_critical_mb} MB</span></div>
              <div className="check-item"><span>Emergency action</span><span className="check-state pending">sebelum {policy.database_emergency_mb} MB</span></div>
            </div>
          ) : <div className="empty-state">Policy Zero-Cost belum tersedia.</div>}
        </article>

        <article className="panel">
          <h3>Backup & Archive Readiness</h3>
          <p className="panel-subtitle">Registry sudah siap, tetapi status tidak akan hijau sebelum backup dan restore benar-benar diuji.</p>
          <div className="check-list">
            <div className="check-item">
              <span>Backup<small className="item-subtext">{latestBackup ? `${latestBackup.backup_run_number} · ${formatDateTime(latestBackup.created_at)}` : "Belum pernah dijalankan"}</small></span>
              <span className={`check-state ${stateClass(backupState)}`}>{backupState}</span>
            </div>
            <div className="check-item"><span>Cold archive</span><span className={`check-state ${stateClass(snapshot?.archive_status ?? "")}`}>{snapshot?.archive_status ?? "NOT_CONFIGURED"}</span></div>
            <div className="check-item">
              <span>Restore test<small className="item-subtext">{latestRestore ? `${latestRestore.restore_test_number} · ${formatDateTime(latestRestore.created_at)}` : "Belum pernah diuji"}</small></span>
              <span className={`check-state ${stateClass(restoreState)}`}>{restoreState}</span>
            </div>
            <div className="check-item"><span>Auto pruning</span><span className="check-state pending">DISABLED</span></div>
          </div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Zero-Cost Guardrails</h3>
          <p className="panel-subtitle">Target internal, bukan klaim bahwa provider tidak akan pernah mengubah paket gratis.</p>
          {policy ? <div className="check-list">
            <div className="check-item"><span>Supabase egress target</span><span className="check-state">&lt; {formatMb(policy.supabase_egress_target_mb)} MB/bulan</span></div>
            <div className="check-item"><span>Cloudflare dynamic request target</span><span className="check-state">&lt; {new Intl.NumberFormat("id-ID").format(policy.cloudflare_dynamic_target_per_day)}/hari</span></div>
            <div className="check-item"><span>R2 storage target</span><span className="check-state">&lt; {formatMb(policy.r2_storage_target_mb / 1024)} GB</span></div>
            <div className="check-item"><span>Paid-plan auto upgrade</span><span className="check-state">DILARANG</span></div>
          </div> : <div className="empty-state">Policy belum tersedia.</div>}
        </article>

        <article className="panel">
          <h3>Langkah Berikutnya</h3>
          <p className="panel-subtitle">Urutan aman sebelum Cloudflare menjadi kandidat production.</p>
          <div className="check-list">
            <div className="check-item"><span>ZC-1 Architecture Baseline</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>ZC-2 Capacity Monitor</span><span className="check-state">READ ONLY</span></div>
            <div className="check-item"><span>ZC-3 Backup Registry</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>ZC-3 First Off-site Backup</span><span className="check-state pending">BUTUH OTORISASI R2</span></div>
            <div className="check-item"><span>ZC-4 Restore Drill</span><span className="check-state pending">PENDING</span></div>
            <div className="check-item"><span>ZC-5 Cloudflare App Pilot</span><span className="check-state pending">PENDING</span></div>
          </div>
        </article>
      </section>

      <section className="panel section-panel">
        <h3>Catatan Operasional</h3>
        <p className="panel-subtitle">
          Snapshot saat ini hanya baseline. Growth trend belum dihitung sampai kita memiliki beberapa snapshot terjadwal.
          Registry backup/restore sudah tersedia, tetapi belum ada backup nyata. Tidak ada data yang akan dihapus hanya
          karena status berubah menjadi WARNING/CRITICAL. Archive/pruning memerlukan workflow, verification, restore test,
          dan persetujuan terpisah.
        </p>
      </section>
    </>
  );
}
