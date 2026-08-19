import Link from "next/link";
import { requirePermission } from "@/lib/auth/permissions";
import { generateUatRecoveryLinkAction } from "./actions";

export const dynamic = "force-dynamic";

const errorMessages: Record<string, string> = {
  "invalid-request": "Email atau scope Manager tidak valid.",
  "development-only": "Direct UAT Recovery hanya diizinkan pada organisasi DEVELOPMENT DEMO-KDKMP-DEV.",
  "lookup-failed": "Lookup Auth gagal. Coba lagi setelah memeriksa runtime log.",
  "user-not-found": "User Auth tidak ditemukan.",
  "profile-not-found": "Profile aplikasi untuk user tersebut tidak ditemukan.",
  "scope-denied": "User berada di luar organisasi Manager atau bukan ACTIVE.",
  "protected-user": "MANAGER dan BOARD tidak boleh dipulihkan melalui jalur operasional umum.",
  "link-failed": "Supabase tidak dapat menghasilkan recovery link.",
};

export default async function UatRecoveryPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  await requirePermission("USER_UPDATE");
  const params = await searchParams;

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Identity &amp; Access · DEVELOPMENT/UAT</p>
          <h1>Direct UAT Recovery</h1>
          <p>
            Jalur MANAGER-only untuk membuat recovery link Supabase tanpa email/SMTP. Hanya user operasional ACTIVE dalam organisasi DEVELOPMENT Manager yang dapat diproses; MANAGER dan BOARD tetap dilindungi.
          </p>
        </div>
        <span className="status-pill">DEVELOPMENT ONLY</span>
      </section>

      {params.error && errorMessages[params.error] ? <div className="alert-error" style={{ marginBottom: 18 }}>{errorMessages[params.error]}</div> : null}

      <section className="panel section-panel" style={{ maxWidth: 760 }}>
        <h3>Buat recovery link langsung</h3>
        <p className="panel-subtitle">
          Setelah dikirim, browser langsung membuka halaman aktivasi KDKMP. Tidak ada email yang dikirim dan SMTP tidak dipakai.
        </p>
        <form action={generateUatRecoveryLinkAction} className="form-stack">
          <div className="field">
            <label htmlFor="uat-recovery-email">Email user operasional</label>
            <input id="uat-recovery-email" name="email" type="email" required autoComplete="off" placeholder="nama+uat-role@gmail.com" />
          </div>
          <button className="primary-button" type="submit">Buat Recovery Link &amp; Lanjut Aktivasi</button>
        </form>
        <p className="form-note"><Link href="/dashboard/access">Kembali ke User &amp; Akses</Link></p>
      </section>
    </>
  );
}
