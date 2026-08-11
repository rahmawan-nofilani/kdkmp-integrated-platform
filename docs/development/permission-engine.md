# Permission Resolution Engine

Status: **PHASE 1 FOUNDATION**

## Tujuan

Permission engine menentukan apakah user yang sedang login boleh melakukan suatu tindakan. Role tidak digunakan sebagai pemeriksaan tunggal.

## Urutan keputusan

```text
Authenticated user
→ profile ACTIVE?
→ permission code exists?
→ active explicit DENY?  → DENY
→ active explicit ALLOW? → ALLOW
→ active role grants permission? → ALLOW
→ otherwise DENY
```

Dengan demikian, explicit `DENY` mempunyai prioritas paling tinggi.

## Implementasi

Database menyediakan RPC:

`has_permission(p_permission_code text) -> boolean`

Fungsi menggunakan `SECURITY INVOKER`, bukan `SECURITY DEFINER`, sehingga tidak memperoleh hak superuser tambahan. RLS membatasi `user_roles`, `user_permissions`, dan `role_permissions` yang dapat dibaca oleh user.

Aplikasi menyediakan:

- `hasPermission(code)` untuk conditional UI/read behavior;
- `requirePermission(code)` untuk route/server authorization;
- `/forbidden` untuk hasil akses ditolak.

## Prinsip penting

Menyembunyikan menu tidak dianggap sebagai security control. Route, Server Action, API endpoint, dan database policy tetap harus memeriksa authorization pada sisi server.

## Data Scope

Permission menjawab **apa yang boleh dilakukan**. Data Scope menjawab **data mana yang boleh disentuh**. Scope engine merupakan lapisan berikutnya dan tidak boleh digantikan oleh permission engine ini.
