import Link from "next/link";
import { notFound } from "next/navigation";
import { requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asCooperativeClient } from "@/types/cooperative-core";

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

export default async function MemberDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requirePermission("MEMBER_VIEW");
  const { id } = await params;
  const { supabase } = await requireAccessContext();
  const db = asCooperativeClient(supabase);

  const [memberResult, historyResult] = await Promise.all([
    db
      .from("members")
      .select("id,member_number,full_name,status,membership_date,termination_date,notes,created_at,updated_at,organization_node_id")
      .eq("id", id)
      .maybeSingle(),
    db
      .from("member_status_history")
      .select("id,from_status,to_status,effective_at,reason,changed_by,created_at")
      .eq("member_id", id)
      .order("effective_at", { ascending: false }),
  ]);

  const member = memberResult.data;
  if (!member) notFound();
  const history = historyResult.data ?? [];

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Member Traceability</p>
          <h1>{member.full_name}</h1>
          <p>
            Detail ini berasal dari master keanggotaan dan status history append-only. Tidak ada tombol hapus histori.
          </p>
        </div>
        <Link className="text-link" href="/dashboard/members" prefetch>Kembali ke Anggota</Link>
      </section>

      <section className="metric-grid">
        <article className="metric-card">
          <div className="metric-label">Status Saat Ini</div>
          <div className="metric-value metric-text">{statusLabels[member.status] ?? member.status}</div>
          <div className="metric-note">Sumber: members.status.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Nomor Anggota</div>
          <div className="metric-value metric-text">{member.member_number ?? "BELUM DITETAPKAN"}</div>
          <div className="metric-note">Format final masih dapat mengikuti kebijakan organisasi.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Tanggal Keanggotaan</div>
          <div className="metric-value metric-text">{member.membership_date ? new Date(member.membership_date).toLocaleDateString("id-ID") : "—"}</div>
          <div className="metric-note">Terisi otomatis saat pertama menjadi ACTIVE.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Histori Status</div>
          <div className="metric-value">{history.length}</div>
          <div className="metric-note">Setiap transisi mempunyai timestamp dan actor reference.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Timeline Status</h3>
          <p className="panel-subtitle">Urutan terbaru ke terlama. Alasan wajib pada transition tertentu.</p>
          {history.length > 0 ? (
            <div className="check-list">
              {history.map((entry) => (
                <div className="check-item" key={entry.id}>
                  <span>
                    {entry.from_status ? `${statusLabels[entry.from_status] ?? entry.from_status} → ` : "Mulai → "}
                    <strong>{statusLabels[entry.to_status] ?? entry.to_status}</strong>
                    <small className="item-subtext">
                      {new Date(entry.effective_at).toLocaleString("id-ID")} · {entry.reason ?? "Tanpa alasan tambahan"}
                    </small>
                  </span>
                  <span className="check-state">HISTORY</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">Belum ada status history yang terlihat.</div>
          )}
        </article>

        <aside className="panel">
          <h3>Informasi Master</h3>
          <div className="check-list">
            <div className="check-item"><span>Dibuat</span><span>{new Date(member.created_at).toLocaleString("id-ID")}</span></div>
            <div className="check-item"><span>Update terakhir</span><span>{new Date(member.updated_at).toLocaleString("id-ID")}</span></div>
            <div className="check-item"><span>Tanggal akhir</span><span>{member.termination_date ? new Date(member.termination_date).toLocaleDateString("id-ID") : "—"}</span></div>
          </div>
          <div className="empty-state" style={{ marginTop: 16 }}>
            <strong>Catatan:</strong><br />
            {member.notes ?? "Belum ada catatan."}
          </div>
          <p className="panel-subtitle" style={{ marginTop: 16, marginBottom: 0 }}>
            NIK, dokumen identitas, saldo, simpanan, dan pinjaman tidak berada di tabel master ini.
          </p>
        </aside>
      </section>
    </>
  );
}
