import Link from "next/link";

const messages: Record<string, string> = {
  "invalid-link": "Link aktivasi tidak lengkap atau formatnya tidak dikenali.",
  "verification-failed": "Link aktivasi tidak dapat diverifikasi. Link mungkin sudah digunakan atau kedaluwarsa.",
};

export default async function AuthErrorPage({
  searchParams,
}: {
  searchParams: Promise<{ reason?: string }>;
}) {
  const params = await searchParams;
  const message = params.reason ? messages[params.reason] : undefined;

  return (
    <main className="login-panel" style={{ minHeight: "100vh" }}>
      <section className="login-card">
        <p className="eyebrow">Aktivasi Gagal</p>
        <h2>Link akun tidak dapat digunakan</h2>
        <p className="intro">
          {message ?? "Verifikasi akun belum berhasil."} Jangan membagikan link
          aktivasi kepada orang lain. Jika Anda memang pengguna yang diundang,
          mintalah pengelola mengirim undangan baru.
        </p>

        <Link
          className="primary-button"
          href="/login"
          style={{ display: "grid", placeItems: "center" }}
        >
          Kembali ke Login
        </Link>
      </section>
    </main>
  );
}
