import type { EmailOtpType } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { activateUser } from "./actions";

export const dynamic = "force-dynamic";

const ALLOWED_TYPES = new Set<EmailOtpType>(["invite", "recovery"]);

export default async function ActivatePage({
  searchParams,
}: {
  searchParams: Promise<{ token_hash?: string; type?: string }>;
}) {
  const params = await searchParams;
  const tokenHash = params.token_hash?.trim();
  const rawType = params.type?.trim() as EmailOtpType | undefined;

  if (!tokenHash || !rawType || !ALLOWED_TYPES.has(rawType)) {
    redirect("/auth/error?reason=invalid-link");
  }

  const isRecovery = rawType === "recovery";

  return (
    <main className="login-panel" style={{ minHeight: "100vh" }}>
      <section className="login-card">
        <p className="eyebrow">Aktivasi Akun</p>
        <h2>{isRecovery ? "Konfirmasi pemulihan password" : "Konfirmasi undangan KDKMP"}</h2>
        <p className="intro">
          Token baru akan dipakai setelah Anda menekan tombol di bawah. Membuka link
          email saja tidak menghabiskan token, sehingga pemindaian otomatis layanan
          email tidak dapat menyelesaikan aktivasi atas nama Anda.
        </p>

        <form action={activateUser} className="form-stack">
          <input type="hidden" name="token_hash" value={tokenHash} />
          <input type="hidden" name="type" value={rawType} />
          <button className="primary-button" type="submit">
            {isRecovery ? "Lanjutkan & Buat Password Baru" : "Aktifkan Akun & Buat Password"}
          </button>
          <p className="form-note">
            Setelah verifikasi berhasil, Anda akan diminta membuat password minimal
            12 karakter. Role dan data scope tidak berubah oleh proses ini.
          </p>
        </form>
      </section>
    </main>
  );
}
