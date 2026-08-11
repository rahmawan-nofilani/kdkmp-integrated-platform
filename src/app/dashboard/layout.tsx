import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { logout } from "./actions";

export const dynamic = "force-dynamic";

type NavProps = {
  canViewMembers: boolean;
  canViewCooperative: boolean;
  canViewMembershipFinance: boolean;
  canViewFinancialProducts: boolean;
  canViewAccounting: boolean;
  canViewApprovals: boolean;
  canViewUsers: boolean;
  canViewAudit: boolean;
  mobile?: boolean;
};

function NavigationLinks({
  canViewMembers,
  canViewCooperative,
  canViewMembershipFinance,
  canViewFinancialProducts,
  canViewAccounting,
  canViewApprovals,
  canViewUsers,
  canViewAudit,
  mobile = false,
}: NavProps) {
  const prefix = mobile ? "mobile-" : "";

  return (
    <nav className={`${prefix}nav`} aria-label={mobile ? "Navigasi ponsel" : "Navigasi utama"}>
      <div className={`${prefix}nav-section`}>Utama</div>
      <Link className={`${prefix}nav-link`} href="/dashboard" prefetch>Dashboard</Link>
      <Link className={`${prefix}nav-link`} href="/dashboard/organization" prefetch>Organisasi & Unit</Link>

      <div className={`${prefix}nav-section`}>Koperasi</div>
      {canViewMembers ? <Link className={`${prefix}nav-link`} href="/dashboard/members" prefetch>Anggota</Link> : null}
      {canViewCooperative ? <Link className={`${prefix}nav-link`} href="/dashboard/cooperative" prefetch>Kelembagaan & RAT</Link> : null}
      {canViewMembershipFinance ? <Link className={`${prefix}nav-link`} href="/dashboard/membership-finance" prefetch>Modal Keanggotaan</Link> : null}

      <div className={`${prefix}nav-section`}>Keuangan</div>
      {canViewAccounting ? <Link className={`${prefix}nav-link`} href="/dashboard/accounting" prefetch>Akuntansi</Link> : null}
      {canViewFinancialProducts ? <Link className={`${prefix}nav-link`} href="/dashboard/financial-products" prefetch>Produk Simpan Pinjam</Link> : null}
      <span className={`${prefix}nav-link disabled`}>Transaksi Simpan Pinjam · gate belum aktif</span>

      <div className={`${prefix}nav-section`}>Operasional</div>
      <span className={`${prefix}nav-link disabled`}>Penjualan · berikutnya</span>
      <span className={`${prefix}nav-link disabled`}>Persediaan · berikutnya</span>

      <div className={`${prefix}nav-section`}>Kontrol</div>
      {canViewApprovals ? <Link className={`${prefix}nav-link`} href="/dashboard/approvals" prefetch>Approval & SoD</Link> : null}
      {canViewUsers ? <Link className={`${prefix}nav-link`} href="/dashboard/access" prefetch>User & Akses</Link> : null}
      {canViewAudit ? <Link className={`${prefix}nav-link`} href="/dashboard/audit" prefetch>Audit</Link> : null}
    </nav>
  );
}

export default async function DashboardLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const { email, profile, roles, permissionCodes } = await requireAccessContext();
  const canViewMembers = permissionCodes.includes("MEMBER_VIEW");
  const canViewCooperative = permissionCodes.some((permission) => ["GOVERNANCE_VIEW", "RAT_VIEW", "SHU_VIEW"].includes(permission));
  const canViewMembershipFinance = permissionCodes.includes("MEMBERSHIP_FINANCE_VIEW");
  const canViewFinancialProducts = permissionCodes.includes("FINANCIAL_PRODUCT_VIEW");
  const canViewAccounting = permissionCodes.includes("ACCOUNTING_VIEW");
  const canViewApprovals = permissionCodes.includes("APPROVAL_VIEW");
  const canViewUsers = permissionCodes.includes("USER_VIEW");
  const canViewAudit = permissionCodes.includes("AUDIT_VIEW");

  const displayName = typeof profile.full_name === "string" && profile.full_name.trim().length > 0 ? profile.full_name : "Pengguna KDKMP";
  const roleLabel = roles.map((role) => role.name).join(", ");
  const initials = displayName.split(" ").filter(Boolean).slice(0, 2).map((word) => word[0]?.toUpperCase()).join("") || "KD";
  const navigationProps = { canViewMembers, canViewCooperative, canViewMembershipFinance, canViewFinancialProducts, canViewAccounting, canViewApprovals, canViewUsers, canViewAudit };

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-brand"><strong>KDKMP</strong><span>Integrated Management Platform</span></div>
        <NavigationLinks {...navigationProps} />
        <div className="sidebar-footer"><small>Approval & SoD Foundation</small><small>Policy activation: governance gate</small></div>
      </aside>

      <div className="workspace">
        <div className="mobile-bar">
          <div className="mobile-brand"><strong>KDKMP</strong><span>Manager Workspace</span></div>
          <details className="mobile-menu">
            <summary className="mobile-menu-trigger" aria-label="Buka menu navigasi"><span aria-hidden="true">☰</span><span>Menu</span></summary>
            <div className="mobile-menu-panel">
              <div className="mobile-user-card">
                <div className="avatar" aria-hidden="true">{initials}</div>
                <div className="mobile-user-meta"><strong>{displayName}</strong><span>{roleLabel || email}</span></div>
              </div>
              <NavigationLinks {...navigationProps} mobile />
              <form action={logout} className="mobile-logout-form"><button className="mobile-logout-button" type="submit">Keluar dari aplikasi</button></form>
            </div>
          </details>
        </div>

        <header className="topbar">
          <div className="topbar-title"><strong>KDKMP Digital Operating System</strong><span>Cooperative Core + Accounting + Approval Control + Financial Product Configuration</span></div>
          <div className="user-box">
            <div className="avatar" aria-hidden="true">{initials}</div>
            <div className="user-meta"><strong>{displayName}</strong><span>{roleLabel || email}</span></div>
            <form action={logout}><button className="logout-button" type="submit">Keluar</button></form>
          </div>
        </header>

        <main className="content">{children}</main>
      </div>
    </div>
  );
}
