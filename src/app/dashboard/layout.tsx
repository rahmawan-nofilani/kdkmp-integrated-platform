import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { logout } from "./actions";

export const dynamic = "force-dynamic";

export default async function DashboardLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();
  const subject = data?.claims?.sub;

  if (error || !subject) {
    redirect("/login");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name,status")
    .eq("auth_user_id", subject)
    .maybeSingle();

  const claims = data.claims as Record<string, unknown>;
  const email = typeof claims.email === "string" ? claims.email : "Akun KDKMP";
  const displayName = profile?.full_name || "Pengguna KDKMP";
  const initials = displayName
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase())
    .join("") || "KD";

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <strong>KDKMP</strong>
          <span>Integrated Management Platform</span>
        </div>

        <nav className="nav" aria-label="Navigasi utama">
          <div className="nav-section">Utama</div>
          <Link className="nav-link active" href="/dashboard">
            <span>Dashboard</span>
          </Link>

          <div className="nav-section">Operasional</div>
          <span className="nav-link disabled"><span>Anggota · berikutnya</span></span>
          <span className="nav-link disabled"><span>Penjualan · berikutnya</span></span>
          <span className="nav-link disabled"><span>Persediaan · berikutnya</span></span>
          <span className="nav-link disabled"><span>Simpan Pinjam · berikutnya</span></span>

          <div className="nav-section">Kontrol</div>
          <span className="nav-link disabled"><span>User & Akses · berikutnya</span></span>
          <span className="nav-link disabled"><span>Audit · berikutnya</span></span>
        </nav>

        <div className="sidebar-footer">
          <small>Phase 1 · Development Environment</small>
          <small>Regulasi: pending validation</small>
        </div>
      </aside>

      <div className="workspace">
        <header className="topbar">
          <div className="topbar-title">
            <strong>KDKMP Digital Operating System</strong>
            <span>Identity & Organization Foundation</span>
          </div>

          <div className="user-box">
            <div className="avatar" aria-hidden="true">{initials}</div>
            <div className="user-meta">
              <strong>{displayName}</strong>
              <span>{email}</span>
            </div>
            <form action={logout}>
              <button className="logout-button" type="submit">Keluar</button>
            </form>
          </div>
        </header>

        <main className="content">{children}</main>
      </div>
    </div>
  );
}
