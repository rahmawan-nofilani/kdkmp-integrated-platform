# Data Scope Resolution Engine

Status: **PHASE 1 FOUNDATION**

## Tujuan

Permission menjawab **apa yang boleh dilakukan**. Data Scope menjawab **terhadap data yang mana tindakan tersebut boleh dilakukan**.

Contoh:

```text
USER punya MEMBER_VIEW
+
COOPERATIVE_SCOPE = KDKMP ABC
=
USER boleh melihat anggota KDKMP ABC, bukan semua anggota platform
```

## Scope types

- `PLATFORM_SCOPE` — seluruh platform; sangat terbatas untuk peran teknis/eksekutif tertentu.
- `REGION_SCOPE` — node wilayah dan seluruh turunannya.
- `COOPERATIVE_SCOPE` — KDKMP dan node/unit di bawah koperasi tersebut.
- `UNIT_SCOPE` — satu unit usaha tertentu.
- `OWN_DATA_ONLY` — hanya data yang dimiliki user sendiri.
- `ASSIGNED_RECORDS_ONLY` — hanya record yang secara eksplisit ditugaskan kepada profile user.

## Hierarki

Untuk `REGION_SCOPE` dan `COOPERATIVE_SCOPE`, database memakai struktur parent-child `organization_nodes`. Target node dinyatakan valid jika node scope merupakan ancestor dari target.

## Security design

Resolver inti berada pada schema non-exposed `app_private` sebagai `SECURITY DEFINER` dengan:

- explicit `auth.uid()` validation;
- profile harus `ACTIVE`;
- fixed empty `search_path`;
- tidak dapat dipanggil anon/public;
- hanya wrapper public `SECURITY INVOKER` yang diekspos sebagai RPC `has_data_scope(...)`.

## Fail closed

Jika tidak ada user, profile tidak aktif, unit/node target tidak valid, atau tidak ada scope yang cocok, hasil adalah `false`.

## Application helpers

- `hasDataScope(target)` — mengecek target data.
- `requireDataScope(target)` — menghentikan route/action jika target berada di luar scope.

## Aturan penggunaan

Untuk operasi bisnis yang sensitif, authorization minimal adalah:

```text
Authentication
+ Active Profile
+ Permission
+ Data Scope
+ Workflow State
+ Segregation of Duties
+ Regulatory/Module Gate (jika berlaku)
```
