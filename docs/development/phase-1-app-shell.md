# Phase 1 Application Shell

Status: **IN DEVELOPMENT**

Dokumen ini menjelaskan Phase 1 dengan bahasa sederhana untuk pemilik proyek non-programmer.

## Apa yang sedang dibangun?

Tahap ini membuat pintu masuk dan kerangka utama aplikasi sebelum modul bisnis seperti Anggota, POS, Gudang, dan Simpan Pinjam diaktifkan.

Alurnya:

```text
Login
  ↓
Supabase Authentication
  ↓
Session/JWT validation
  ↓
Profile ACTIVE?
  ↓
Role aktif tersedia?
  ↓
Dashboard
```

Jika profil belum aktif, role belum ditetapkan, akun suspended, atau akses sudah berakhir, user diarahkan ke halaman **Access Pending**, bukan dashboard.

## Komponen yang sudah disiapkan

- Next.js + TypeScript application foundation;
- Supabase browser/server clients;
- server-side login action;
- cookie/session refresh through Next.js Proxy;
- protected dashboard shell;
- access-pending state;
- logout flow;
- database RLS and least-privilege Data API grants;
- role/permission foundation;
- GitHub CI for typecheck and build;
- manual one-time lockfile generator for reproducible npm dependencies.

## Yang belum dibuat

- public self-registration (sengaja tidak disediakan);
- Manager User Management UI;
- delegated permission administration;
- real organization bootstrap data;
- operational KDKMP data;
- POS, inventory, procurement, accounting, Simpan Pinjam transactions;
- final regulatory configuration;
- production deployment.

## Mengapa belum ada angka usaha di dashboard?

Dashboard belum menampilkan omzet, profit, stok, simpanan, pinjaman, atau KPI karena transaction engine sumber datanya belum aktif. Sistem tidak menggunakan angka palsu untuk terlihat lengkap.

## Prinsip bootstrap user pertama

User operasional tidak mendaftar sendiri. User pertama dibuat melalui proses bootstrap terkontrol. Setelah bootstrap selesai, pembuatan user operasional berikutnya akan dilakukan oleh user berwenang melalui User Management sesuai permission dan audit rules.

## Regulasi

Semua detail regulasi yang belum diberikan tetap diberi status **DRAFT / PENDING LEGAL VALIDATION**. Struktur regulatory authorization sudah tersedia sehingga aturan resmi dapat ditambahkan kemudian tanpa membongkar fondasi aplikasi.
