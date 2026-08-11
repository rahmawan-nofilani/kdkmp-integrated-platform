# Supabase Database Types

Status: **PHASE 1 DEVELOPMENT STANDARD**

`src/types/database.ts` adalah snapshot TypeScript dari schema Supabase DEVELOPMENT.

## Mengapa diperlukan?

Tanpa generated database types, query aplikasi dapat salah menulis nama tabel/kolom dan baru gagal saat runtime. Dengan tipe ini, banyak kesalahan dapat dihentikan saat TypeScript CI berjalan.

## Aturan

1. Jangan mengedit `src/types/database.ts` untuk mengubah schema database.
2. Perubahan schema harus dilakukan melalui migration SQL yang tercatat.
3. Setelah migration diterapkan, tipe database harus digenerate ulang dari Supabase.
4. Supabase browser client, server client, dan proxy client semuanya menggunakan generic `Database` yang sama.
5. CI typecheck harus lolos sebelum perubahan schema/application di-merge.

## Urutan yang benar

```text
Business rule
→ migration SQL
→ apply migration to DEVELOPMENT
→ security/performance advisor
→ regenerate database types
→ update application
→ dependency audit
→ typecheck
→ build
→ Pull Request
```

## Catatan

Generated types tidak menggantikan RLS, backend authorization, validation, atau audit rules. Tipe hanya membantu memastikan struktur data yang digunakan kode sesuai dengan schema database saat ini.
