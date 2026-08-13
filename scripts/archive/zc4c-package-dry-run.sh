#!/usr/bin/env bash
set -euo pipefail

for cmd in jq openssl tar gzip sha256sum stat; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Required command missing: $cmd" >&2; exit 1; }
done

RUN_ID="${ARCHIVE_DRY_RUN_ID:-local-dry-run}"
SOURCE_COMMIT="${ARCHIVE_DRY_RUN_COMMIT:-0000000000000000000000000000000000000000}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

STAGING="$WORKDIR/staging"
READBACK="$WORKDIR/readback"
mkdir -p "$STAGING" "$READBACK/extracted"

cat > "$STAGING/pos_transactions.jsonl" <<'JSONL'
{"sale_id":"SYNTH-001","closed_at":"2026-07-01T09:00:00Z","gross_total":125000,"payment_total":125000}
{"sale_id":"SYNTH-002","closed_at":"2026-07-12T10:30:00Z","gross_total":175000,"payment_total":175000}
{"sale_id":"SYNTH-003","closed_at":"2026-07-28T13:15:00Z","gross_total":95000,"payment_total":95000}
JSONL

SOURCE_ROWS="$(wc -l < "$STAGING/pos_transactions.jsonl" | tr -d ' ')"
SOURCE_SHA256="$(sha256sum "$STAGING/pos_transactions.jsonl" | awk '{print $1}')"
GROSS_TOTAL="$(jq -s 'map(.gross_total) | add' "$STAGING/pos_transactions.jsonl")"
PAYMENT_TOTAL="$(jq -s 'map(.payment_total) | add' "$STAGING/pos_transactions.jsonl")"

if [ "$SOURCE_ROWS" -le 0 ] || [ "$GROSS_TOTAL" -ne "$PAYMENT_TOTAL" ]; then
  echo "Synthetic source reconciliation failed." >&2
  exit 1
fi

jq -n \
  --arg archive_run_number "ARC-DRYRUN-${RUN_ID}" \
  --arg application_commit_sha "$SOURCE_COMMIT" \
  --arg content_sha256 "$SOURCE_SHA256" \
  --argjson row_count "$SOURCE_ROWS" \
  --argjson gross_total "$GROSS_TOTAL" \
  --argjson payment_total "$PAYMENT_TOTAL" \
  '{
    archive_format_version: 1,
    environment: "CI_DRY_RUN_SYNTHETIC_ONLY",
    archive_run_number: $archive_run_number,
    tenant_id: "SYNTHETIC-TENANT",
    cooperative_id: "SYNTHETIC-KDKMP",
    archive_class: "POS_TRANSACTION",
    source_period: {
      from: "2026-07-01T00:00:00Z",
      to: "2026-08-01T00:00:00Z",
      timezone: "Asia/Jakarta"
    },
    source_schema_version: "zc4c-dry-run-v1",
    application_commit_sha: $application_commit_sha,
    tables: [{
      name: "pos_transactions.jsonl",
      row_count: $row_count,
      content_sha256: $content_sha256
    }],
    reconciliation: {
      status: "PASSED",
      gross_total: $gross_total,
      payment_total: $payment_total
    }
  }' > "$STAGING/source-manifest.json"

SOURCE_MANIFEST_SHA256="$(sha256sum "$STAGING/source-manifest.json" | awk '{print $1}')"

tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -C "$STAGING" -cf - pos_transactions.jsonl source-manifest.json \
  | gzip -n > "$WORKDIR/archive.tar.gz"

ARCHIVE_DRY_RUN_PASSPHRASE="$(openssl rand -hex 32)"
export ARCHIVE_DRY_RUN_PASSPHRASE
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
  -in "$WORKDIR/archive.tar.gz" \
  -out "$WORKDIR/archive.tar.gz.enc" \
  -pass env:ARCHIVE_DRY_RUN_PASSPHRASE

PACKAGE_SIZE="$(stat -c%s "$WORKDIR/archive.tar.gz.enc")"
PACKAGE_SHA256="$(sha256sum "$WORKDIR/archive.tar.gz.enc" | awk '{print $1}')"
OBJECT_KEY="dry-run/${RUN_ID}/archive.tar.gz.enc"

if [ "$PACKAGE_SIZE" -le 0 ] || [ -z "${OBJECT_KEY//[[:space:]]/}" ]; then
  echo "Dry-run package identity is invalid." >&2
  exit 1
fi

jq -n \
  --arg archive_run_number "ARC-DRYRUN-${RUN_ID}" \
  --arg object_key "$OBJECT_KEY" \
  --arg package_sha256 "$PACKAGE_SHA256" \
  --arg source_manifest_sha256 "$SOURCE_MANIFEST_SHA256" \
  --argjson size_bytes "$PACKAGE_SIZE" \
  --argjson source_rows "$SOURCE_ROWS" \
  '{
    archive_format_version: 1,
    environment: "CI_DRY_RUN_SYNTHETIC_ONLY",
    archive_run_number: $archive_run_number,
    archive_class: "POS_TRANSACTION",
    storage_provider: "DRY_RUN_LOCAL_ONLY",
    object_key: $object_key,
    package: {
      encrypted: true,
      cipher: "AES-256-CBC",
      kdf: "PBKDF2",
      pbkdf2_iterations: 200000,
      size_bytes: $size_bytes,
      sha256: $package_sha256
    },
    source_manifest_sha256: $source_manifest_sha256,
    source_row_counts: { pos_transactions: $source_rows },
    reconciliation_checks: { status: "PASSED", row_counts_match: true }
  }' > "$WORKDIR/archive-manifest.json"

cp "$WORKDIR/archive.tar.gz.enc" "$READBACK/archive.tar.gz.enc"
READBACK_SIZE="$(stat -c%s "$READBACK/archive.tar.gz.enc")"
READBACK_SHA256="$(sha256sum "$READBACK/archive.tar.gz.enc" | awk '{print $1}')"

if [ "$READBACK_SIZE" -ne "$PACKAGE_SIZE" ] || [ "$READBACK_SHA256" != "$PACKAGE_SHA256" ]; then
  echo "Encrypted package local read-back mismatch." >&2
  exit 1
fi

openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in "$READBACK/archive.tar.gz.enc" \
  -out "$READBACK/archive.tar.gz" \
  -pass env:ARCHIVE_DRY_RUN_PASSPHRASE

gzip -dc "$READBACK/archive.tar.gz" | tar -xf - -C "$READBACK/extracted"

RECOVERED_MANIFEST_SHA256="$(sha256sum "$READBACK/extracted/source-manifest.json" | awk '{print $1}')"
RECOVERED_CONTENT_SHA256="$(sha256sum "$READBACK/extracted/pos_transactions.jsonl" | awk '{print $1}')"
RECOVERED_ROWS="$(wc -l < "$READBACK/extracted/pos_transactions.jsonl" | tr -d ' ')"

if [ "$RECOVERED_MANIFEST_SHA256" != "$SOURCE_MANIFEST_SHA256" ] \
   || [ "$RECOVERED_CONTENT_SHA256" != "$SOURCE_SHA256" ] \
   || [ "$RECOVERED_ROWS" -ne "$SOURCE_ROWS" ]; then
  echo "Recovered synthetic payload does not match source evidence." >&2
  exit 1
fi

jq -n \
  --argjson source_total "$SOURCE_ROWS" \
  --argjson recovered_total "$RECOVERED_ROWS" \
  '{
    row_count_checks: {
      row_counts_match: ($source_total == $recovered_total),
      source_total: $source_total,
      recovered_total: $recovered_total
    },
    integrity_checks: {
      sha256_match: true,
      decryptable: true,
      manifest_match: true,
      content_sha256_match: true
    }
  }' > "$WORKDIR/recovery-evidence.json"

jq -e '
  .row_count_checks.row_counts_match == true
  and .integrity_checks.sha256_match == true
  and .integrity_checks.decryptable == true
  and .integrity_checks.manifest_match == true
  and .integrity_checks.content_sha256_match == true
' "$WORKDIR/recovery-evidence.json" >/dev/null

unset ARCHIVE_DRY_RUN_PASSPHRASE

echo "ZC-4C synthetic package dry-run PASSED"
echo "source_rows=$SOURCE_ROWS"
echo "package_size_bytes=$PACKAGE_SIZE"
echo "package_sha256=$PACKAGE_SHA256"
echo "object_key=$OBJECT_KEY"
echo "remote_database_touched=false"
echo "external_storage_touched=false"
