# Controlled Invitation & First-Password Flow

Status: **PHASE 1 DEVELOPMENT STANDARD**

## Tujuan

KDKMP tidak menyediakan public self-signup untuk user operasional. User dibuat/diundang melalui proses terkontrol, lalu user membuat password sendiri melalui link verifikasi.

## Alur

```text
Authorized invitation
→ email invitation
→ /auth/confirm?token_hash=...&type=invite
→ Supabase verifies token server-side
→ authenticated activation session
→ /set-password
→ user chooses password
→ /access-pending
→ profile + role + data scope provisioning
→ dashboard access
```

Authentication dan authorization sengaja dipisahkan. Email yang sudah terverifikasi dan password yang sudah dibuat belum berarti user boleh masuk dashboard operasional.

## Required hosted Supabase email-template configuration

Setelah aplikasi memiliki URL deployment, hosted Supabase Dashboard harus diarahkan ke URL aplikasi tersebut.

Untuk template **Invite user**, gunakan link berbasis token hash yang menuju aplikasi:

```html
<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=invite">
  Aktifkan akun KDKMP
</a>
```

Untuk flow recovery password di masa depan, pola yang disiapkan adalah:

```html
<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery">
  Atur ulang password KDKMP
</a>
```

## Password policy aplikasi Phase 1

- minimal 12 karakter;
- password dan confirmation harus sama;
- password dipilih sendiri oleh user;
- aplikasi tidak menyimpan plaintext password;
- user disarankan tidak memakai ulang password akun pribadi penting.

Kebijakan ini adalah **application security baseline**, bukan klaim regulasi pemerintah.

## Security controls

1. Token hash diverifikasi server-side melalui Supabase Auth.
2. Token tidak diteruskan setelah verifikasi.
3. `/set-password` hanya dapat dibuka jika session/JWT sudah valid.
4. Password update dilakukan melalui Server Action.
5. Setelah password berhasil dibuat, user diarahkan ke `access-pending`.
6. Profile ACTIVE + active role assignment tetap wajib sebelum dashboard terbuka.
7. Permission + data scope tetap menjadi lapisan authorization setelah login.

## Bootstrap Manager pertama

Manager pertama adalah pengecualian bootstrap teknis. Setelah Auth user dibuat melalui mekanisme resmi Supabase, system administrator melakukan satu kali provisioning database untuk:

- membuat `profiles` row ACTIVE;
- menghubungkan ke DEMO organization;
- menetapkan role MANAGER;
- menetapkan DEMO cooperative scope;
- mencatat bootstrap event pada audit trail.

Sesudah Manager pertama aktif, user operasional berikutnya harus dibuat melalui User Management yang tunduk pada permission dan audit.
