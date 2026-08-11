import { requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asCooperativeClient } from "@/types/cooperative-core";
import { changeMemberStatusAction, createMemberAction } from "./actions";

export const dynamic = "force-dynamic";

const statusLabels: Record<string, string> = {
  APPLICANT: "Pendaftar",
  UNDER_REVIEW: "Dalam Review",
  ACTIVE: "Aktif",
  SUSPENDED: "Ditangguhkan",
  INACTIVE: "Tidak Aktif",
  RESIGNED: "Mengundurkan Diri",
  TERMINATED: "Diberhentikan",
  ARCHIVED: "Arsip",
};

const errorMessages: Record<string, string> = {
  "duplicate-number": "Nomor anggota tersebut sudah dipakai pada KDKMP yang sama.",
  "missing-name": "Nama anggota wajib diisi.",
  "node-required": "Sistem tidak dapat menentukan KDKMP tujuan secara otomatis. Periksa Data Scope user.",
  "reason-required": "Perubahan status tersebut wajib disertai alasan.",
  "transition-not-allowed": "Perubahan status tidak sesuai workflow keanggotaan yang aktif.",
  "scope-denied": "Anda tidak memiliki Data Scope untuk anggota tersebut.",
  "invalid-status-request": "Permintaan perubahan status tidak lengkap.",
  system: "Transaksi tidak dapat diproses. Detail teknis tidak ditampilkan ke pengguna.",
};

const successMessages: Record<string, string> = {
  created: "Master anggota berhasil dibuat dengan status Pendaftar.",
  "status-updated": "Status anggota berhasil diperbarui dan histori sudah dicatat.",
};

export default async function MembersPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; success?: string }>;
}) {
  await requirePermission("MEMBER_VIEW");
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  const db = asCooperativeClient(supabase);
  const params = await searchParams;
  const organizationId = profile.organization_id;
  const canCreate = permissionCodes.includes("MEMBER_CREATE");
  const canChangeStatus = permissionCodes.includes("MEMBER_STATUS_CHANGE");

  const [membersResult, transitionsResult] = await Promise.all([
    organizationId
      ? db
          .from("members")
          .select("id,member_number,full_name,status,membership_date,termination_date,notes,organization_id,organization_node_id,created_at")
          .eq("organization_id", organizationId)
          .order("created_at", { ascending: false })
          .limit(100)
      : Promise.resolve({ data: [], error: null }),
    db
      .from("member_status_transition_rules")
      .select("id,organization_id,from_status,to_status,requires_reason,enabled,policy_status,description")
      .eq("enabled", true)
      .eq("policy_status", "ACTIVE")
      .order("from_status"),
  ]);

  const members = membersResult.data ?? [];
  const transitions = transitionsResult.data ?? [];
  const activeCount = members.filter((member) => member.status === "ACTIVE").length;
  const reviewCount = members.filter((member) => ["APPLICANT", "UNDER_REVIEW"].includes(member.status)).length;
  const suspendedCount = members.filter((member) => member.status === "SUSPENDED").length;

  function transitionsFor(status: string) {
    const selected = new Map<string, (typeof transitions)[number]>();
    for (const rule of transitions) {
      if (rule.from_status !== status) continue;
      if (rule.organization_id !== null && rule.organization_id !== organizationId) continue;
      const existing = selected.get(rule.to_status);
      if (!existing || rule.organization_id !== null) selected.set(rule.to_status, rule);
    }
    return Array.from(selected.values());
  }

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Cooperative Core</p>
          <h1>Anggota</h1>
          <p>
            Master keanggotaan yang dapat ditelusuri. Perubahan status tidak menimpa histori lama;
            setiap transisi divalidasi oleh workflow, permission, Data Scope, dan audit trail.
          </p>
        </div>
        <span className="status-pill">PHASE 2</span>
      </section>

      {params.error && errorMessages[params.error] ? (
        <div className="alert-error page-alert">{errorMessages[params.error]}</div>
      ) : null}
      {params.success && successMessages[params.success] ? (
        <div className="alert-success page-alert">{successMessages[params.success]}</div>
      ) : null}

      <section className="metric-grid">
        <article className="metric-card">
          <div className="metric-label">Total Record</div>
          <div className="metric-value">{members.length}</div>
          <div className="metric-note">Maksimum 100 record terbaru pada increment ini.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Anggota Aktif</div>
          <div className="metric-value">{activeCount}</div>
          <div className="metric-note">Status ACTIVE dari sumber transaksi membership.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Perlu Proses</div>
          <div className="metric-value">{reviewCount}</div>
          <div className="metric-note">APPLICANT atau UNDER_REVIEW.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Ditangguhkan</div>
          <div className="metric-value">{suspendedCount}</div>
          <div className="metric-note">Status SUSPENDED; alasan perubahan wajib tercatat.</div>
        </article>
      </section>

      <section className="dashboard-grid member-workspace-grid">
        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Master Anggota</h3>
              <p className="panel-subtitle">Hanya record yang lolos RLS + KDKMP Data Scope yang terlihat.</p>
            </div>
          </div>

          {members.length > 0 ? (
            <div className="data-table-wrap">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Nomor</th>
                    <th>Nama</th>
                    <th>Status</th>
                    <th>Tanggal Anggota</th>
                    <th>Dibuat</th>
                    <th>Aksi</th>
                  </tr>
                </thead>
                <tbody>
                  {members.map((member) => {
                    const allowedTransitions = transitionsFor(member.status);
                    return (
                      <tr key={member.id}>
                        <td>{member.member_number ?? "Belum ditetapkan"}</td>
                        <td><strong>{member.full_name}</strong></td>
                        <td><span className="table-status">{statusLabels[member.status] ?? member.status}</span></td>
                        <td>{member.membership_date ? new Date(member.membership_date).toLocaleDateString("id-ID") : "—"}</td>
                        <td>{new Date(member.created_at).toLocaleDateString("id-ID")}</td>
                        <td>
                          {canChangeStatus && allowedTransitions.length > 0 ? (
                            <details className="row-action-menu">
                              <summary>Ubah status</summary>
                              <form action={changeMemberStatusAction} className="row-action-form">
                                <input type="hidden" name="member_id" value={member.id} />
                                <label>
                                  Status berikutnya
                                  <select name="new_status" required defaultValue="">
                                    <option value="" disabled>Pilih status</option>
                                    {allowedTransitions.map((rule) => (
                                      <option key={rule.id} value={rule.to_status}>
                                        {statusLabels[rule.to_status] ?? rule.to_status}{rule.requires_reason ? " · alasan wajib" : ""}
                                      </option>
                                    ))}
                                  </select>
                                </label>
                                <label>
                                  Alasan / catatan
                                  <input name="reason" type="text" placeholder="Isi bila diperlukan" />
                                </label>
                                <button className="small-button" type="submit">Simpan status</button>
                              </form>
                            </details>
                          ) : (
                            <span className="muted-text">Tidak ada aksi</span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="empty-state">
              Belum ada master anggota. Gunakan form di samping untuk membuat data DEVELOPMENT pertama.
            </div>
          )}
        </article>

        <aside className="panel">
          <h3>Tambah Anggota</h3>
          <p className="panel-subtitle">
            Phase 2 belum meminta NIK atau data identitas sensitif. Nomor anggota boleh dikosongkan sampai format resmi ditetapkan.
          </p>
          {canCreate ? (
            <form action={createMemberAction} className="form-stack compact-form">
              <div className="field">
                <label htmlFor="full_name">Nama lengkap</label>
                <input id="full_name" name="full_name" required maxLength={160} placeholder="Contoh: Anggota Demo 001" />
              </div>
              <div className="field">
                <label htmlFor="member_number">Nomor anggota</label>
                <input id="member_number" name="member_number" maxLength={80} placeholder="Opsional / menunggu format resmi" />
              </div>
              <div className="field">
                <label htmlFor="notes">Catatan</label>
                <textarea id="notes" name="notes" rows={3} maxLength={500} placeholder="Gunakan data DEMO saja pada environment ini." />
              </div>
              <button className="primary-button" type="submit">Buat master anggota</button>
            </form>
          ) : (
            <div className="empty-state">Anda memiliki MEMBER_VIEW tetapi tidak memiliki MEMBER_CREATE.</div>
          )}
          <div className="control-note">
            <strong>Data sensitif:</strong> NIK, dokumen identitas, dan data finansial belum disimpan di master ini. Layer RESTRICTED akan dibuat terpisah.
          </div>
        </aside>
      </section>
    </>
  );
}
