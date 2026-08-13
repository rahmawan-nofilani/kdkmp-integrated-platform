#!/usr/bin/env python3
import gzip, hashlib, io, json, os, shutil, tarfile, tempfile
from collections import Counter
from datetime import datetime
from pathlib import Path

ROOT = Path(os.environ["ZC4D_REPO_ROOT"]) if "ZC4D_REPO_ROOT" in os.environ else Path(__file__).resolve().parents[2]
POLICY = json.loads((ROOT / "config/archive/zc4d-pos-transaction-eligibility-v1.json").read_text())
FIXTURE = json.loads((ROOT / "fixtures/archive/zc4d-pos-relational-synthetic.json").read_text())
RUN = os.getenv("ARCHIVE_REHEARSAL_ID", "local")
COMMIT = os.getenv("ARCHIVE_REHEARSAL_COMMIT", "0" * 40)


def enc(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_jsonl(path, rows):
    Path(path).write_bytes(b"".join(enc(row) for row in sorted(rows, key=lambda row: row["id"])))


def read_jsonl(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line]


def expand(case):
    suffix = f"{case['n']:03d}"
    sale_id = f"SALE-{suffix}"
    payment_id = f"PI-{suffix}"
    inventory_id = f"IM-{suffix}"
    journal_id = f"JE-{suffix}"
    period_id = "AP-AUG" if case["day"].startswith("2026-08") else "AP-JUL"
    return {
        "sale": {
            "id": sale_id,
            "status": case["sale_status"],
            "sync_status": case["sync_status"],
            "completed_at": f"{case['day']}T10:02:00+07:00",
            "total_amount": case["amount"],
            "payment_intent_id": payment_id,
            "inventory_movement_id": None if case["missing_inventory"] else inventory_id,
            "journal_entry_id": journal_id,
            "reversal_of_sale_id": "SALE-000" if case["reversal"] else None,
        },
        "sale_line": {"id": f"SL-{suffix}", "sales_transaction_id": sale_id, "line_total": case["amount"]},
        "payment": {"id": payment_id, "source_entity_id": sale_id, "status": case["payment_status"], "amount": case["amount"]},
        "attempt": {"id": f"PA-{suffix}", "payment_intent_id": payment_id, "status": case["payment_status"], "amount": case["amount"]},
        "inventory": None if case["missing_inventory"] else {
            "id": inventory_id,
            "source_entity_id": sale_id,
            "status": case["inventory_status"],
            "reversal_of_movement_id": "IM-000" if case["reversal"] else None,
        },
        "inventory_line": None if case["missing_inventory"] else {"id": f"IML-{suffix}", "inventory_movement_id": inventory_id, "base_quantity": 1},
        "period": {"id": period_id, "status": case["period_status"]},
        "journal": {
            "id": journal_id,
            "accounting_period_id": period_id,
            "source_entity_id": sale_id,
            "status": "POSTED",
            "reversal_of_entry_id": "JE-000" if case["reversal"] else None,
        },
        "journal_lines": [
            {"id": f"JL-{suffix}-1", "journal_entry_id": journal_id, "debit": case["amount"], "credit": 0},
            {"id": f"JL-{suffix}-2", "journal_entry_id": journal_id, "debit": 0, "credit": case["amount"] if case["journal_balanced"] else case["amount"] - 10000},
        ],
    }


def reasons(case):
    policy = POLICY
    sale = case["sale"]
    output = []
    start = datetime.fromisoformat(policy["source_period"]["from"])
    end = datetime.fromisoformat(policy["source_period"]["to_exclusive"])
    if sale["status"] != policy["sale"]["required_status"]:
        output.append("SALE_STATUS_NOT_COMPLETED")
    if sale["sync_status"] != policy["sale"]["required_sync_status"]:
        output.append("SALE_NOT_SYNCED")
    if not (start <= datetime.fromisoformat(sale["completed_at"]) < end):
        output.append("OUTSIDE_SOURCE_PERIOD")
    if sale["reversal_of_sale_id"]:
        output.append("SALE_HAS_REVERSAL_REFERENCE")
    if case["payment"]["status"] != policy["payment"]["intent_required_status"]:
        output.append("PAYMENT_NOT_SETTLED")
    if case["attempt"]["status"] != policy["payment"]["attempt_required_status"]:
        output.append("PAYMENT_ATTEMPT_NOT_SETTLED")
    if case["inventory"] is None:
        output.append("INVENTORY_MOVEMENT_MISSING")
    elif case["inventory"]["status"] != policy["inventory"]["required_status"]:
        output.append("INVENTORY_NOT_POSTED")
    elif case["inventory"]["reversal_of_movement_id"]:
        output.append("INVENTORY_HAS_REVERSAL_REFERENCE")
    if case["period"]["status"] != policy["accounting"]["required_period_status"]:
        output.append("ACCOUNTING_PERIOD_NOT_HARD_CLOSED")
    if case["journal"]["status"] != policy["accounting"]["journal_required_status"]:
        output.append("JOURNAL_NOT_POSTED")
    if case["journal"]["reversal_of_entry_id"]:
        output.append("JOURNAL_HAS_REVERSAL_REFERENCE")
    if sum(line["debit"] for line in case["journal_lines"]) != sum(line["credit"] for line in case["journal_lines"]):
        output.append("JOURNAL_UNBALANCED")
    return sorted(set(output))


def selected(cases, ids):
    ids = set(ids)
    output = {name: [] for name in [
        "accounting_periods", "sales_transactions", "sales_transaction_lines",
        "payment_intents", "payment_attempts", "inventory_movements",
        "inventory_movement_lines", "journal_entries", "journal_lines",
    ]}
    periods = {}
    for case in cases:
        if case["sale"]["id"] not in ids:
            continue
        output["sales_transactions"].append(case["sale"])
        output["sales_transaction_lines"].append(case["sale_line"])
        output["payment_intents"].append(case["payment"])
        output["payment_attempts"].append(case["attempt"])
        output["journal_entries"].append(case["journal"])
        output["journal_lines"] += case["journal_lines"]
        if case["inventory"]:
            output["inventory_movements"].append(case["inventory"])
            output["inventory_movement_lines"].append(case["inventory_line"])
        periods[case["period"]["id"]] = case["period"]
    output["accounting_periods"] = list(periods.values())
    return output


def validate(data, ids):
    ids = set(ids)
    if {row["id"] for row in data["sales_transactions"]} != ids:
        raise RuntimeError("CANDIDATE_SET_MISMATCH")
    if any(row["sales_transaction_id"] not in ids for row in data["sales_transaction_lines"]):
        raise RuntimeError("ORPHAN_SALES_LINE")
    if any(row["payment_intent_id"] not in {parent["id"] for parent in data["payment_intents"]} for row in data["payment_attempts"]):
        raise RuntimeError("ORPHAN_PAYMENT_ATTEMPT")
    if any(row["inventory_movement_id"] not in {parent["id"] for parent in data["inventory_movements"]} for row in data["inventory_movement_lines"]):
        raise RuntimeError("ORPHAN_INVENTORY_LINE")
    if any(row["journal_entry_id"] not in {parent["id"] for parent in data["journal_entries"]} for row in data["journal_lines"]):
        raise RuntimeError("ORPHAN_JOURNAL_LINE")
    sales = sum(row["total_amount"] for row in data["sales_transactions"])
    payments = sum(row["amount"] for row in data["payment_intents"])
    attempts = sum(row["amount"] for row in data["payment_attempts"])
    debit = sum(row["debit"] for row in data["journal_lines"])
    credit = sum(row["credit"] for row in data["journal_lines"])
    if len({sales, payments, attempts, debit, credit}) != 1:
        raise RuntimeError("CONTROL_TOTAL_MISMATCH")
    return {"sales": sales, "payments": payments, "attempts": attempts, "debit": debit, "credit": credit}


def make_tar(files, output):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for path in sorted(files, key=lambda item: item.name):
            raw = path.read_bytes()
            info = tarfile.TarInfo(path.name)
            info.size = len(raw)
            info.mtime = info.uid = info.gid = 0
            info.uname = info.gname = ""
            archive.addfile(info, io.BytesIO(raw))
    buffer.seek(0)
    with open(output, "wb") as raw_file:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_file, mtime=0) as zipped:
            shutil.copyfileobj(buffer, zipped)


def extract(source, destination):
    destination = Path(destination).resolve()
    with tarfile.open(source, "r:gz") as archive:
        for member in archive.getmembers():
            target = (destination / member.name).resolve()
            if not member.isfile() or destination not in target.parents:
                raise RuntimeError("UNSAFE_MEMBER")
            extracted = archive.extractfile(member)
            if extracted is None:
                raise RuntimeError("UNREADABLE_MEMBER")
            target.write_bytes(extracted.read())


def main():
    if POLICY.get("environment") != "CI_REHEARSAL_SYNTHETIC_ONLY" or POLICY.get("real_data_execution") != "BLOCKED":
        raise RuntimeError("POLICY_NOT_FAIL_CLOSED")
    cases = [expand(case) for case in FIXTURE["cases"]]
    rejected = {case["sale"]["id"]: reasons(case) for case in cases}
    ids = sorted(sale_id for sale_id, rejection in rejected.items() if not rejection)
    if ids != ["SALE-001", "SALE-002"] or sum(bool(value) for value in rejected.values()) != 6:
        raise RuntimeError("SELECTION_PROOF_FAILED")
    required = {
        "SALE_STATUS_NOT_COMPLETED", "SALE_NOT_SYNCED", "OUTSIDE_SOURCE_PERIOD",
        "ACCOUNTING_PERIOD_NOT_HARD_CLOSED", "SALE_HAS_REVERSAL_REFERENCE",
        "JOURNAL_UNBALANCED", "INVENTORY_MOVEMENT_MISSING",
    }
    seen = Counter(reason for values in rejected.values() for reason in values)
    if not required <= set(seen):
        raise RuntimeError("NEGATIVE_CASE_MISSING")
    chosen = selected(cases, ids)
    controls = validate(chosen, ids)
    with tempfile.TemporaryDirectory(prefix="zc4d-") as temp:
        work = Path(temp)
        stage = work / "stage"
        readback = work / "readback"
        stage.mkdir()
        readback.mkdir()
        files, tables = [], []
        for name, rows in chosen.items():
            path = stage / f"{name}.jsonl"
            write_jsonl(path, rows)
            files.append(path)
            tables.append({"name": name, "row_count": len(rows), "sha256": sha(path)})
        evidence = stage / "candidate-selection-evidence.json"
        evidence.write_bytes(enc({
            "candidate_ids": ids,
            "rejected": [{"sale_id": key, "reasons": value} for key, value in sorted(rejected.items()) if value],
            "reason_counts": dict(sorted(seen.items())),
        }))
        files.append(evidence)
        manifest = stage / "source-manifest.json"
        manifest.write_bytes(enc({
            "archive_format_version": 2,
            "archive_run_number": f"ARC-REHEARSAL-{RUN}",
            "policy_version": POLICY["policy_version"],
            "source_period": POLICY["source_period"],
            "application_commit_sha": COMMIT,
            "tables": tables,
            "selection_evidence_sha256": sha(evidence),
            "control_totals": controls,
            "real_data_execution": "BLOCKED",
            "prune_authorization": "NOT_GRANTED",
        }))
        files.append(manifest)
        package_a = work / "archive.tar.gz"
        package_b = work / "archive-repeat.tar.gz"
        make_tar(files, package_a)
        make_tar(files, package_b)
        if sha(package_a) != sha(package_b):
            raise RuntimeError("NON_DETERMINISTIC_PACKAGE")
        readback_package = readback / package_a.name
        shutil.copyfile(package_a, readback_package)
        if sha(readback_package) != sha(package_a):
            raise RuntimeError("READBACK_MISMATCH")
        extracted = readback / "extracted"
        extracted.mkdir()
        extract(readback_package, extracted)
        recovered = {table["name"]: read_jsonl(extracted / f"{table['name']}.jsonl") for table in tables}
        if validate(recovered, ids) != controls or sha(extracted / evidence.name) != sha(evidence):
            raise RuntimeError("RECONSTRUCTION_MISMATCH")
        print("ZC-4D candidate + relational reconstruction rehearsal PASSED")
        print("candidate_sales=2")
        print("rejected_sales=6")
        print("selected_tables=9")
        print("deterministic_package=PASSED")
        print("relational_reconstruction=PASSED")
        print("prune_eligible=false")
        print("real_data_execution=BLOCKED")
        print("remote_database_touched=false")
        print("external_storage_touched=false")


if __name__ == "__main__":
    main()
