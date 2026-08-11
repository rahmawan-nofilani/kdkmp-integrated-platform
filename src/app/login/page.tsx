import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { login } from "./actions";

export const dynamic = "force-dynamic";

const errorMessages: Record<string, string> = {
  missing: "Email dan password wajib diisi.",
  invalid: "Email atau password tidak valid.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (data?.claims?.sub) {
    redirect("/dashboard");
  }

  const params = await searchParams;
  const errorMessage = params.error ? errorMessages[params.error] : undefined;

  return (
    <main className="login-page">
      <section className="login-brand" aria-label="KDKMP Integrated Platform">
        <div className="brand-mark">
          <span className="brand-dot" aria-hidden="true" />
          KDKMP INTEGRATED PLATFORM
        </div>

        <div className="login-copy">
          <p className="eyebrow" style={{ color: "#f4c9cc" }}>Digital Operating System</p>
          <h1>Satu sistem untuk mengelola operasi koperasi secara tertib.</h1>
          <p>
            Identitas, anggota, unit usaha, persediaan, keuangan, simpan pinjam,
            tata kelola, audit, dan pelaporan dibangun di atas satu fondasi data
            yang dapat ditelusuri.
          </p>
        </div>

        <div className="login-brand-footer">
          DEVELOPMENT ENVIRONMENT · Data operasional asli belum digunakan.
        </div>
      </section>

      <section className="login-panel">
        <div className="login-card">
          <p className="eyebrow">Akses Terotorisasi</p>
          <h2>Masuk ke sistem</h2>
          <p className="intro">
            Gunakan akun yang diberikan oleh pengelola KDKMP. Pendaftaran akun
            publik tidak tersedia.
          </p>

          <form action={login} className="form-stack">
            {errorMessage ? <div className="alert-error">{errorMessage}</div> : null}

            <div className="field">
              <label htmlFor="email">Email</label>
              <input
                id="email"
                name="email"
                type="email"
                autoComplete="username"
                placeholder="nama@contoh.id"
                required
              />
            </div>

            <div className="field">
              <label htmlFor="password">Password</label>
              <input
                id="password"
                name="password"
                type="password"
                autoComplete="current-password"
                placeholder="Masukkan password"
                required
              />
            </div>

            <button className="primary-button" type="submit">
              Masuk
            </button>

            <p className="form-note">
              Akses dicatat dan tunduk pada role, permission, data scope, serta
              kebijakan keamanan KDKMP.
            </p>
          </form>
        </div>
      </section>
    </main>
  );
}
