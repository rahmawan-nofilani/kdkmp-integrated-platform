# KopdesKu — Kontrak Arsitektur & Logika End-to-End (Checkpoint v3)
Tanggal: 11 November 2026
Basis: `KopdesKu_Checkpoint_MASTER_v2_2026-11-11.md`
Status: **rancangan implementasi; bukan persetujuan penerapan produksi**.

## 1. Tujuan dan identitas desain
- Satu aplikasi Next.js / Supabase Postgres; 7 koperasi sebagai tenant logis. Masing-masing hanya melihat data bisnis sendiri.
- KopdesKu memakai logo SVG asli dari repo Kedungharjo dan UI **Red Premium Enterprise**. HP/tablet sebagai prioritas kasir, PC sebagai ruang kerja manajer/admin.
- Pusat hanya mengelola organisasi, pengguna, perangkat, dan kesehatan/keamanan platform. Tidak ada tampilan penjualan/NIK/kas/gudang lintas koperasi bagi admin pusat. Akses khusus DBA/service role mesti diaudit dan dipisah.
- Source of truth awal tetap `kdkmp-integrated-platform` (Postgres), bukan backend D1 dari repo referensi.

## 2. Lima pengenal yang tidak boleh tertukar
| Identitas | Milik siapa | Digunakan untuk | Tidak boleh dipakai untuk |
|---|---|---|---|
| `organization_id` | Satu KDKMP | Mengisolasi semua record operasional | ID warga atau nomor kartu |
| `person_id` | Individu | Identitas stabil dan riwayat hak per NIK | Mengidentifikasi KK secara keseluruhan |
| `household_id` | Keluarga/KK | Hubungan anggota dan satu kartu aktif | Menghitung kuota per NIK |
| `card_id` / token QR | Satu kartu KK | Mencari keluarga, revoke/reissue | Payload NIK atau verifikasi kelayakan subsidi |
| `sale_id` + `external_sale_id` | Satu transaksi bisnis | Integrasi POS, anti-duplikasi, reversal | Membuat dua pencatatan keuangan paralel |

**Batas data:** bisnis/KDKMP memegang data operasionalnya; pengenal global lintas desa hanya boleh diproses oleh layanan trusted yang terpisah, minimal dan berizin. Desain identitas global tidak memindahkan akses bisnis ke admin pusat.

## 3. Modul dan kontrak relasi data
### 3.1 Organisasi dan hak akses — M1–M2
Eksisting: `organizations`, `organization_nodes`, `organization_units`, `profiles`, `roles`, `permissions`, `data_scopes`, `user_scope_assignments`.
- Setiap operasi bisnis harus memeriksa `auth_user`, `profile.status`, `profile.organization_id`, permission, scope node/unit, serta status organisasi.
- `PLATFORM_SCOPE` bukan wildcard bisnis. Pengguna platform tidak boleh memiliki akses bisnis, bahkan bila mendapat permission/COOPERATIVE_SCOPE secara keliru.
- Gunakan composite foreign key `(organization_id, <foreign_id>)` pada seluruh hubungan bisnis baru; jika record menyilang tenant, commit ditolak.
- Pusat melihat registry organisasi melalui API/RPC *platform metadata* khusus (belum dibangun); jangan membuka RLS transaksi untuk sekadar membuat dashboard pusat.

### 3.2 Warga, KK dan status anggota — M3
Rencana tabel baru (belum dibuat oleh patch M1):
- `resident_persons` (PK UUID, org ID, kunci pencocokan NIK terlindungi, data minimum, status verifikasi).
- `resident_households` (PK UUID, org ID, referensi KK terlindungi, alamat/RT/RW/dusun, status keluarga).
- `resident_household_members` (household, person, role, valid_from/valid_until; **riwayat**, tidak overwrite bebas).
- `resident_registration_events` (domisili, pindah, sumber, persetujuan/verifikasi, waktu, actor).
- `cooperative_memberships` (person_id, organization_id, member_id eksisting `public.members`, persyaratan, status berlaku).
Satu warga terdaftar **tidak otomatis menjadi anggota koperasi resmi** dan tidak otomatis berhak subsidi.

**Catatan desain:** data person antar-tenant **belum** boleh digabung langsung. Bila perlu pencocokan lintas desa, gunakan *blind-index/token-match* oleh layanan tersendiri; kebijakan keamanan, otoritas data, dan audit harus ditetapkan sebelum koneksi lintas tenant dibuat. NIK/nomor KK asli tidak ada dalam QR, log, URL atau laporan reguler.

### 3.3 Kartu digital / penerbitan / distribusi — M3
- `household_cards`: 1 `ACTIVE` per `(organization_id, household_id)` **unique partial index**, kartu dikaitkan ke KK stabil, bukan permanen ke kepala keluarga.
- QR menyimpan token tidak bermakna; server menyimpan hash token. Reissue menonaktifkan token lama, tetapi *tidak menghapus hak/riwayat NIK*.
- `card_issuance_events`: dibuat/dicetak/dicabut; aktor dan alasan.
- `card_distribution_events`: daftar RT/dusun, petugas, hasil penyerahan dan tanggal; export batch per RT memuat data minimum.
- Scan KK → pilih individu penerima → (jika boleh) catat pengambil berbeda → validasi kebijakan. Kartu saja tidak memverifikasi NIK atau subsidi.

### 3.4 Impor dan ekspor — M3/M4/M8
- Menu `Pusat Data` untuk Warga, KK, Anggota resmi, Produk, Pemasok, Stok awal dan Laporan.
- Tahapan: template → upload privat → mapping kolom → cek format/duplikasi → preview → approval → commit → error report + audit.
- Setiap baris diikat ke `organization_id` dari sesi server, **tidak** dari nilai bebas dalam Excel. Simpan job-id dan idempotency key, boleh ulang aman.
- Ekspor default menyamarkan NIK; ekspor data sensitif/QR massal role-gated, ada masa kedaluwarsa file dan log audit. CSV/Excel perlu pencegahan formula injection.

### 3.5 Produk, pemasok dan stok — M4
Eksisting: `inventory_items`, `suppliers`, `warehouses`, pergerakan dan POS. Penambahan skema harus mengaudit kolom yang tersedia agar tidak menduplikasi tabel.
- Identitas: kategori → merek → varian → ukuran → satuan beli/jual → SKU/barcode. Pemasok utama opsional, penerimaan stok menyimpan pemasok aktual.
- Satu SKU dapat dijual **reguler atau melalui beberapa program bersyarat**, sesuai aturan. Harga/versi aturan bukan kolom boolean tunggal pada master barang.
- Kuota stok khusus program membutuhkan `stock_allocation` atau lot/batch yang terhubung ke penerimaan, dan tidak boleh diam-diam dijual reguler.
- Perlu keputusan HPP FIFO / rata-rata tertimbang dan penelusuran supplier pada penjualan.

### 3.6 Subsidi, kuota, lokasi dan perwakilan — M5
- Program memiliki `program_id`, sumber aturan, versi aturan, status, periode berlaku, SKU/kelompok barang, kuota (per NIK), unit normal, periode (harian, kalender, rolling), cakupan (KDKMP/lintas program), lokasi penyaluran, hak perwakilan.
- Hak penerima mengacu data dari penyelenggara yang sah. **Domisili ≠ lokasi lahan ≠ alokasi ≠ penebusan**.
- Pembelian subsidi harus per NIK penerima; identitas pengambil terpisah jika perwakilan sah. Jika penebusan lintas KDKMP diperlukan, gunakan verifikasi minimal oleh layanan trusted tanpa memberi akses transaksi tenant lain.
- Aturan internal boleh dikonfigurasi. Aturan wajib regulator tidak boleh dinonaktifkan/diturunkan oleh Admin lokal.
- Reversal kuota hanya mengikuti kebijakan program dan audit; tidak otomatis membebaskan hak yang sudah digunakan.

### 3.7 POS, pembayaran dan sinkronisasi — M6/M9
Eksisting: POS tunai, shift, retur, cash ledger dan jurnal.
- Satu keranjang dapat berisi barang reguler dan subsidi; verifikasi ulang ketika commit, setelah otorisasi, kuota, stok dan harga dinyatakan sah.
- Satu sumber kebenaran transaksi; satu `sale_id` dan idempotency key. Post stock + kas + jurnal + kuota menggunakan *single DB transaction* bila semuanya berada dalam KopdesKu.
- POS asli sebagai sistem utama **sementara** (perlu konfirmasi adapter/API). Sinkronisasi dengan POS lain menggunakan `external_source_id`, `external_sale_id`, outbox/inbox, retry aman, dan status `PENDING/ACKNOWLEDGED/FAILED/NEEDS_RECONCILIATION`; **jangan** mengirim klik pembayaran ke dua aplikasi sekaligus.
- Jika POS resmi tertutup, tahap awal hanya impor transaksi dan rekonsiliasi; satu scan dua keranjang tidak boleh dijanjikan.
- Untuk subsidi online cross-tenant, gagal verifikasi = tahan transaksi, bukan meloloskan otomatis.

### 3.8 Laporan dinamis — M8
- Laporan membaca transaksi/ledger *committed*, tidak mengubah angka mentah. Filter pemasok, kategori, merek, SKU, program, kasir, periode, gerai, gudang.
- Judul, catatan, kelompok, urutan, template, kop, dan tanda tangan dapat diedit; perubahan versi tercatat.
- Ekspor Excel, PDF, Word, CSV sesuai peran; filter `organization_id` selalu ditegakkan backend.
- Laporan penjualan **berdasarkan pemasok asal** membutuhkan lot/receipt traceability, bukan satu pemasok default.

## 4. Alur keberhasilan dan kegagalan (satu alur tidak boleh terputus)
1. Koperasi aktif dan operator dalam role/scope sah → akses menu sesuai peran.
2. Warga/KK masuk lewat import atau manual → `PENDING_VERIFICATION` → verified → QR KK terbit → didistribusikan RT.
3. Produk dan pemasok didaftarkan → penerimaan ber-`receipt_id` → stok di lokasi, batch/sumber tercatat.
4. POS scan produk → jika reguler, lanjut; jika program, scan QR KK → pilih NIK penerima dan pengambil (bila sah) → periksa hak, lokasi, kuota dan stok.
5. **Commit sekali**: transaksi, kuota, stok, kas, jurnal → struk, outbox integrasi. Bila salah satu gagal di dalam KopdesKu, semua rollback.
6. Adapter POS asli melakukan ack/retry/rekonsiliasi; kegagalan sync tidak membuat transaksi kedua.
7. Manager melihat audit/selisih → koreksi melalui workflow -> laporan dan ekspor dari ledger yang konsisten.

**Kasus gagal minimal:** impor duplikat, kartu revoked, pindah KK, kasir beda desa, kuota bersama habis, dua kasir rebut kuota, pembayaran timeout, POS asli offline, retur parsial, stok supplier bercampur, user dicabut akses saat sesi berjalan.

## 5. Pekerjaan yang sudah disentuh oleh increment M1 ini
- Ditambahkan migrasi `database/migrations/20261111080000_kopdesku_m1_business_scope_isolation.sql` untuk menolak wildcard platform pada helper bisnis dan mengunci org/node/unit.
- Ditambahkan uji `database/tests/kopdesku_m1_tenant_scope_negative.sql` (synthetic rollback fixture).
- Ditambahkan GitHub Actions `.github/workflows/kopdesku-m1-tenant-isolation-ci.yml` untuk replay migrasi dan menjalankan uji.
- **BELUM** dibuktikan dengan PostgreSQL runtime di sesi ini; harap jalankan CI database pada branch fitur dan Supabase staging terpisah. Tidak ada deployment atau penggunaan data NIK riil.

## 6. Gerbang sebelum M2/M3
- CI replay migrasi dan test negatif harus PASS (termasuk row-level RLS pada tabel bisnis & RPC write).
- Audit `service_role`, helper lain dengan `SECURITY DEFINER`, storage bucket policies, dan `profiles` update grant secara menyeluruh; pemeriksaan PLATFORM_SCOPE ini **belum keseluruhan audit keamanan**.
- Tentukan apakah scope pembatasan subsidi lokal vs 7 KDKMP dapat dipilih per program, sumber alokasi resmi, dan siapa *trusted identity matching service*; jangan bangun data global NIK sebelum kebijakannya sah.
- Baru mulai wizard registrasi 7 tenant dan layanan warga/KK berdasarkan hasil keamanan.
