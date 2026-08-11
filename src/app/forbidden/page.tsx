import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function ForbiddenPage({
  searchParams,
}: {
  searchParams: Promise<{ permission?: string }>;
}) {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();

  if (error || !data?.claims?.sub) {
    redirect("/login");
  }

  const params = await searchParams;

  return (
    <main className="login-panel" style={{ minHeight: "100vh" }}>
      <section className="login-card">
        <p className="eyebrow">Akses Ditolak</p>
        <h2>Anda tidak memiliki kewenangan untuk tindakan ini</h2>
        <p className="intro">
          Sistem memeriksa role, permission aktif, override user, dan status akun.
          Menu yang terlihat bukan bukti bahwa suatu transaksi diizinkan; keputusan
          akses tetap dilakukan pada server/database.
        </p>

        {params.permission ? (
          <div className="empty-state" style={{ marginBottom: 20 }}>
            Permission yang diperlukan: <strong>{params.permission}</strong>
          </div>
        ) : null}

        <Link className="primary-button" href="/dashboard" style={{ display: "grid", placeItems: "center" }}>
          Kembali ke Dashboard
        </Link>
      </section>
    </main>
  );
}
