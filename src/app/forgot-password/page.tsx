import Link from "next/link";
import { requestPasswordRecovery } from "./actions";

export const dynamic = "force-dynamic";

export default async function ForgotPasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; sent?: string }>;
}) {
  const params = await searchParams;
  const missing = params.error === "missing";
  const sent = params.sent === "1";

  return (
    <main className="login-panel" style={{ minHeight: "100vh" }}>
      <section className="login-card">
        <p className="eyebrow">Pemulihan Akses</p>
        <h2>Buat atau reset password</h2>
        <p className="intro">
          Masukkan email akun KDKMP. Jika akun memenuhi syarat, sistem akan mengirim
          email pemulihan. Tautan email hanya membuka halaman konfirmasi dan tidak
          menghabiskan token sampai Anda menekan tombol aktivasi.
        </p>

        {missing ? <div className="alert-error">Email wajib diisi.</div> : null}
        {sent ? (
          <div className="alert-success">
            Jika akun tersedia, email pemulihan telah diminta. Periksa kotak masuk dan spam.
          </div>
        ) : null}

        <form action={requestPasswordRecovery} className="form-stack">
          <div className="field">
            <label htmlFor="email">Email</label>
            <input id="email" name="email" type="email" autoComplete="email" required />
          </div>
          <button className="primary-button" type="submit">Kirim Link Pemulihan</button>
        </form>

        <p className="form-note">
          <Link href="/login">Kembali ke halaman masuk</Link>
        </p>
      </section>
    </main>
  );
}
