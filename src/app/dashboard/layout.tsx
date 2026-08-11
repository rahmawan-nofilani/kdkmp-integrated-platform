import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { logout } from "./actions";

export const dynamic = "force-dynamic";

export default async function DashboardLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const { email, profile, roles } = await requireAccessContext();

  const displayName =
    typeof profile.full_name === "string" && profile.full_name.trim().length > 0
      ? profile.full_name
      : "Pengguna KDKMP";
  const roleLabel = roles
    .map((role: { name: string }) => role.name)
    .join(", ");
  const initials =
    displayName
      .split(" ")
      .filter(Boolean)
      .slice(0, 2)
      .map((word: string) => word[0]?.toUpperCase())
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
              <span>{roleLabel || email}</span>
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
