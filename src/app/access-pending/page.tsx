import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { logoutPendingUser } from "./actions";

export const dynamic = "force-dynamic";

export default async function AccessPendingPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();

  if (error || !data?.claims?.sub) {
    redirect("/login");
  }

  return (
    <main className="login-panel" style={{ minHeight: "100vh" }}>
      <section className="login-card">
        <p className="eyebrow">Status Akses</p>
        <h2>Akun belum dapat mengakses aplikasi</h2>
        <p className="intro">
          Identitas Anda berhasil diverifikasi, tetapi profil operasional atau role
          aktif belum tersedia. Kondisi ini juga berlaku untuk akun yang sedang
          ditangguhkan atau sudah tidak aktif.
        </p>

        <div className="empty-state" style={{ marginBottom: 20 }}>
          Pengelola KDKMP perlu mengaktifkan profil dan menetapkan role sesuai
          kewenangan. Tidak ada akses otomatis hanya karena akun berhasil login.
        </div>

        <form action={logoutPendingUser}>
          <button className="primary-button" type="submit" style={{ width: "100%" }}>
            Kembali ke Login
          </button>
        </form>
      </section>
    </main>
  );
}
