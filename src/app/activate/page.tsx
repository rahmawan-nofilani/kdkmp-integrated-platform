import { redirect } from "next/navigation";
import { activateInvitedUser } from "./actions";

export const dynamic = "force-dynamic";

export default async function ActivatePage({
  searchParams,
}: {
  searchParams: Promise<{ token_hash?: string; type?: string }>;
}) {
  const params = await searchParams;
  const tokenHash = params.token_hash?.trim();
  const type = params.type?.trim();

  if (!tokenHash || type !== "invite") {
    redirect("/auth/error?reason=invalid-link");
  }

  return (
    <main className="login-panel" style={{ minHeight: "100vh" }}>
      <section className="login-card">
        <p className="eyebrow">Aktivasi Akun</p>
        <h2>Konfirmasi undangan KDKMP</h2>
        <p className="intro">
          Klik tombol di bawah untuk mengaktifkan undangan. Token baru akan dipakai
          setelah Anda menekan tombol ini, sehingga pemindaian otomatis dari layanan
          email tidak menghabiskan link aktivasi.
        </p>

        <form action={activateInvitedUser} className="form-stack">
          <input type="hidden" name="token_hash" value={tokenHash} />
          <input type="hidden" name="type" value="invite" />
          <button className="primary-button" type="submit">
            Aktifkan Akun & Buat Password
          </button>
          <p className="form-note">
            Setelah verifikasi berhasil, Anda akan diminta membuat password minimal
            12 karakter. Role dan data scope tetap mengikuti provisioning KDKMP.
          </p>
        </form>
      </section>
    </main>
  );
}
