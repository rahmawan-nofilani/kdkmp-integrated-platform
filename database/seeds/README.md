# Database Seeds

Seed files create controlled DEVELOPMENT data. They are not production migrations and must never be presented as official KDKMP records.

## 001_development_demo_organization.sql

Creates an idempotent synthetic environment:

```text
DEMO Platform
└── DEMO Province
    └── DEMO Regency
        └── DEMO District
            └── DEMO Village
                └── DEMO — KDKMP
                    ├── DEMO — Kantor
                    ├── DEMO — Gerai
                    ├── DEMO — Gudang
                    └── DEMO — Simpan Pinjam
```

It also creates:

- one cooperative-level data scope;
- four unit-level data scopes;
- one own-data scope;
- one assigned-record scope;
- Simpan Pinjam feature module enabled for the DEMO unit;
- Simpan Pinjam authorization placeholder with status `PENDING_VALIDATION`.

## Important distinction

`feature_modules.enabled = true` means the software capability exists for the unit.

It does **not** mean the activity is legally authorized. Regulated transaction workflows must separately require a valid `regulatory_authorizations` state before they can operate.

## Production rule

Do not copy DEMO codes/names into production. Production organization, region hierarchy, units, permits, and regulatory basis must come from validated organizational documents and applicable regulations.
