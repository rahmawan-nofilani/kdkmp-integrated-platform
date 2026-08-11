import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function ForbiddenPage({
  searchParams,
}: {
  searchParams: Promise<{ permission?: string; reason?: string }>;
}) {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();

  if (error || !data?.claims?.sub) {
    redirect("/login");
  }

  const params = await searchParams;
  const scopeDenied = params.reason === "data-scope";

  return (
    <main className="login-panel" style={{ minHeight: "100vh" }}>
      <section className="login-card">
        <p className="eyebrow">Akses Ditolak</p>
        <h2>Anda tidak memiliki kewenangan untuk tindakan ini</h2>
        <p className="intro">
          Sistem memeriksa status akun, role, permission, override user, dan data
          scope. Menu yang terlihat bukan bukti bahwa transaksi atau data tertentu
          diizinkan; keputusan akses tetap dilakukan pada server/database.
        </p>

        {params.permission ? (
          <div className="empty-state" style={{ marginBottom: 20 }}>
            Permission yang diperlukan: <strong>{params.permission}</strong>
          </div>
        ) : null}

        {scopeDenied ? (
          <div className="empty-state" style={{ marginBottom: 20 }}>
            Permission tindakan mungkin tersedia, tetapi data yang diminta berada
            di luar data scope aktif user.
          </div>
        ) : null}

        <Link className="primary-button" href="/dashboard" style={{ display: "grid", placeItems: "center" }}>
          Kembali ke Dashboard
        </Link>
      </section>
    </main>
  );
}
