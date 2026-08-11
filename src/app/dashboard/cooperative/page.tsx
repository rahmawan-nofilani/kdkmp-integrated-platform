import Link from "next/link";
import { requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asCooperativeClient } from "@/types/cooperative-core";

export const dynamic = "force-dynamic";

export default async function CooperativePage() {
  await requirePermission("GOVERNANCE_VIEW");
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  const db = asCooperativeClient(supabase);
  const organizationId = profile.organization_id;
  const canViewRat = permissionCodes.includes("RAT_VIEW");
  const canViewShu = permissionCodes.includes("SHU_VIEW");

  const [bodiesResult, assignmentsResult, meetingsResult, resolutionsResult, shuPeriodsResult] = await Promise.all([
    organizationId
      ? db.from("governance_bodies").select("id,code,name,body_type,status,effective_from,effective_until,organization_node_id").eq("organization_id", organizationId).order("name")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("governance_assignments").select("id,person_name_snapshot,status,term_start,term_end,appointment_reference,governance_body_id,organization_node_id").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(50)
      : Promise.resolve({ data: [], error: null }),
    organizationId && canViewRat
      ? db.from("general_meetings").select("id,code,title,meeting_type,period_year,status,scheduled_at,held_at,venue,organization_node_id").eq("organization_id", organizationId).order("period_year", { ascending: false }).limit(20)
      : Promise.resolve({ data: [], error: null }),
    organizationId && canViewRat
      ? db.from("meeting_resolutions").select("id,resolution_number,title,status,decided_at,meeting_id,organization_node_id").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(20)
      : Promise.resolve({ data: [], error: null }),
    organizationId && canViewShu
      ? db.from("shu_periods").select("id,fiscal_year,status,approved_at,shu_policy_version_id,organization_node_id").eq("organization_id", organizationId).order("fiscal_year", { ascending: false }).limit(20)
      : Promise.resolve({ data: [], error: null }),
  ]);

  const bodies = bodiesResult.data ?? [];
  const assignments = assignmentsResult.data ?? [];
  const meetings = meetingsResult.data ?? [];
  const resolutions = resolutionsResult.data ?? [];
  const shuPeriods = shuPeriodsResult.data ?? [];
  const activeBodies = bodies.filter((body) => body.status === "ACTIVE");
  const activeAssignments = assignments.filter((assignment) => assignment.status === "ACTIVE");

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Cooperative Core</p>
          <h1>Kelembagaan & Tata Kelola</h1>
          <p>
            Jabatan koperasi dipisahkan dari role aplikasi. RAT, keputusan, dan SHU memakai record historis/versioned agar perubahan kebijakan tidak menulis ulang masa lalu.
          </p>
        </div>
        <span className="status-pill">DRAFT POLICY</span>
      </section>

      <section className="metric-grid">
        <article className="metric-card">
          <div className="metric-label">Badan Aktif</div>
          <div className="metric-value">{activeBodies.length}</div>
          <div className="metric-note">Pengurus, Pengawas, komite, atau badan lain dalam scope KDKMP.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Penugasan Aktif</div>
          <div className="metric-value">{activeAssignments.length}</div>
          <div className="metric-note">Assignment organisasi; tidak otomatis memberikan role aplikasi.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">RAT / Rapat</div>
          <div className="metric-value">{meetings.length}</div>
          <div className="metric-note">Record meeting yang lolos RAT_VIEW dan Data Scope.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Periode SHU</div>
          <div className="metric-value">{shuPeriods.length}</div>
          <div className="metric-note">Formula final belum diaktifkan sebelum AD/ART/kebijakan divalidasi.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Struktur Kelembagaan</h3>
              <p className="panel-subtitle">Master badan koperasi dan status masa berlakunya.</p>
            </div>
            <Link className="text-link" href="/dashboard/members" prefetch>Master anggota</Link>
          </div>
          {bodies.length > 0 ? (
            <div className="check-list">
              {bodies.map((body) => (
                <div className="check-item" key={body.id}>
                  <span>{body.name}<small className="item-subtext">{body.body_type} · {body.code}</small></span>
                  <span className={`check-state ${body.status === "ACTIVE" ? "" : "pending"}`}>{body.status}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">
              Struktur Pengurus/Pengawas belum diinput. Schema dan permission engine-nya sudah tersedia; data resmi dapat dimasukkan setelah struktur organisasi final diberikan.
            </div>
          )}
        </article>

        <article className="panel">
          <h3>Penugasan Jabatan</h3>
          <p className="panel-subtitle">Nama disimpan sebagai historical snapshot agar perubahan profil tidak mengubah arsip masa lalu.</p>
          {assignments.length > 0 ? (
            <div className="check-list">
              {assignments.slice(0, 10).map((assignment) => (
                <div className="check-item" key={assignment.id}>
                  <span>{assignment.person_name_snapshot}<small className="item-subtext">{assignment.appointment_reference ?? "Referensi penetapan belum diisi"}</small></span>
                  <span className={`check-state ${assignment.status === "ACTIVE" ? "" : "pending"}`}>{assignment.status}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">Belum ada assignment jabatan pada data DEVELOPMENT.</div>
          )}
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>RAT & Keputusan</h3>
          <p className="panel-subtitle">Meeting, agenda, attendance, dan resolution sudah mempunyai fondasi data terpisah.</p>
          {!canViewRat ? (
            <div className="empty-state">Role Anda tidak mempunyai RAT_VIEW.</div>
          ) : meetings.length > 0 ? (
            <div className="check-list">
              {meetings.map((meeting) => (
                <div className="check-item" key={meeting.id}>
                  <span>{meeting.title}<small className="item-subtext">{meeting.period_year ?? "—"} · {meeting.meeting_type} · {meeting.code}</small></span>
                  <span className={`check-state ${meeting.status === "CLOSED" ? "" : "pending"}`}>{meeting.status}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">Belum ada RAT/rapat yang dicatat. Keputusan final tetap membutuhkan workflow governance, bukan edit tabel langsung.</div>
          )}
          {resolutions.length > 0 ? <p className="panel-footnote">{resolutions.length} resolution terbaru tersedia dalam scope ini.</p> : null}
        </article>

        <article className="panel">
          <h3>SHU Policy Engine</h3>
          <p className="panel-subtitle">Policy → Version → Period. Formula dan bobot tidak akan ditanam permanen di kode.</p>
          {!canViewShu ? (
            <div className="empty-state">Role Anda tidak mempunyai SHU_VIEW.</div>
          ) : shuPeriods.length > 0 ? (
            <div className="check-list">
              {shuPeriods.map((period) => (
                <div className="check-item" key={period.id}>
                  <span>SHU Tahun Buku {period.fiscal_year}<small className="item-subtext">Policy version: {period.shu_policy_version_id ? "terhubung" : "belum ditetapkan"}</small></span>
                  <span className={`check-state ${period.status === "CLOSED" ? "" : "pending"}`}>{period.status}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">
              Belum ada periode SHU. Ini disengaja: formula resmi, bobot, eligibility, dan legal basis masih PENDING ORGANIZATIONAL / REGULATORY VALIDATION.
            </div>
          )}
        </article>
      </section>
    </>
  );
}
