import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { setPassword } from "./actions";

export const dynamic = "force-dynamic";

const errorMessages: Record<string, string> = {
  "too-short": "Password minimal 12 karakter.",
  mismatch: "Konfirmasi password tidak sama.",
  "update-failed": "Password belum dapat disimpan. Silakan buka ulang link undangan atau hubungi pengelola.",
};

export default async function SetPasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();

  if (error || !data?.claims?.sub) {
    redirect("/login");
  }

  const params = await searchParams;
  const errorMessage = params.error ? errorMessages[params.error] : undefined;

  return (
    <main className="login-panel" style={{ minHeight: "100vh" }}>
      <section className="login-card">
        <p className="eyebrow">Aktivasi Akun</p>
        <h2>Buat password akun Anda</h2>
        <p className="intro">
          Identitas email sudah diverifikasi. Buat password yang hanya Anda ketahui.
          Aktivasi password belum otomatis memberikan kewenangan operasional; role
          dan data scope tetap harus ditetapkan oleh pengelola KDKMP.
        </p>

        <form action={setPassword} className="form-stack">
          {errorMessage ? <div className="alert-error">{errorMessage}</div> : null}

          <div className="field">
            <label htmlFor="password">Password baru</label>
            <input
              id="password"
              name="password"
              type="password"
              autoComplete="new-password"
              minLength={12}
              required
            />
          </div>

          <div className="field">
            <label htmlFor="password_confirmation">Ulangi password</label>
            <input
              id="password_confirmation"
              name="password_confirmation"
              type="password"
              autoComplete="new-password"
              minLength={12}
              required
            />
          </div>

          <button className="primary-button" type="submit">Simpan Password</button>

          <p className="form-note">
            Gunakan minimal 12 karakter dan jangan gunakan password yang sama dengan
            akun pribadi penting lainnya.
          </p>
        </form>
      </section>
    </main>
  );
}
