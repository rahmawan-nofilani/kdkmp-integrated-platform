#!/usr/bin/env python3
"""Isolate Cloudflare Workers CPU by public route using narrow time windows.

Safety: this probe sends only unauthenticated GET requests to the existing
DEVELOPMENT pilot and read-only GraphQL analytics queries. It never deploys,
updates, deletes, or reconfigures Cloudflare resources.

The Workers invocations dataset is adaptive/sampled. Route-level results are
therefore diagnostic evidence only; they identify likely hotspots but never
constitute the final Free-plan readiness decision.
"""

from __future__ import annotations

import argparse
import importlib.util
import math
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

SAMPLE_SIZE = 20
MIN_COVERAGE_RATIO = 0.75
BETWEEN_BATCH_SECONDS = 8
INITIAL_INGESTION_WAIT_SECONDS = 150
POLL_SECONDS = 30
MAX_POLLS = 6
WINDOW_PADDING_SECONDS = 2

ROUTES = (
    ("health", "/api/health", 200),
    ("login", "/login", 200),
    ("root", "/", 307),
    ("dashboard_unauth", "/dashboard", 307),
)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Keep redirect responses observable instead of following them."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


NO_REDIRECT_OPENER = urllib.request.build_opener(NoRedirect)


@dataclass
class Batch:
    label: str
    path: str
    expected_status: int
    started: datetime
    ended: datetime


def load_analytics_module():
    path = Path(__file__).with_name("zc5h-readonly-worker-analytics.py")
    spec = importlib.util.spec_from_file_location("zc5j_analytics", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load the read-only analytics module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def request_status(base: str, path: str) -> int:
    req = urllib.request.Request(
        base.rstrip("/") + path,
        method="GET",
        headers={"User-Agent": "kdkmp-zc5j-route-isolation/1.3"},
    )
    try:
        with NO_REDIRECT_OPENER.open(req, timeout=25) as response:
            return int(response.status)
    except urllib.error.HTTPError as exc:
        return int(exc.code)


def run_batch(base: str, label: str, path: str, expected: int) -> Batch:
    started = datetime.now(timezone.utc)
    statuses: list[int] = []
    for _ in range(SAMPLE_SIZE):
        status = request_status(base, path)
        statuses.append(status)
        if status != expected:
            raise RuntimeError(f"{label}: expected HTTP {expected}, received {status}")
    ended = datetime.now(timezone.utc)
    print(
        f"route_batch={label} sample_requests={len(statuses)} expected_http={expected} result=PASS "
        f"window_start={iso(started)} window_end={iso(ended)}",
        flush=True,
    )
    return Batch(label, path, expected, started, ended)


def query_batch(module, account_id: str, token: str, worker: str, batch: Batch):
    start = batch.started - timedelta(seconds=WINDOW_PADDING_SECONDS)
    end = batch.ended + timedelta(seconds=WINDOW_PADDING_SECONDS)
    payload = module._post_graphql(
        token,
        module.QUERY,
        {
            "accountTag": account_id,
            "datetimeStart": iso(start),
            "datetimeEnd": iso(end),
            "scriptName": worker,
        },
    )
    return module.summarize(payload)


def classify_route(module, summary, unit: str) -> tuple[str, float | None, float | None]:
    cpu = module.evaluate_cpu_budget(summary, unit)
    return cpu["gate"], cpu["p50_ms"], cpu["p99_ms"]


def minimum_observed_requests() -> int:
    return math.ceil(SAMPLE_SIZE * MIN_COVERAGE_RATIO)


def self_test() -> None:
    assert SAMPLE_SIZE >= 10
    assert 0.5 <= MIN_COVERAGE_RATIO < 1.0
    assert minimum_observed_requests() == 15
    assert INITIAL_INGESTION_WAIT_SECONDS >= 120
    assert POLL_SECONDS >= 15
    labels = [item[0] for item in ROUTES]
    assert len(labels) == len(set(labels))
    assert {item[2] for item in ROUTES} <= {200, 307}
    handler = NoRedirect()
    assert handler.redirect_request(None, None, 307, "Temporary Redirect", {}, "https://example.invalid") is None
    print("zc5j_route_isolation_self_test=PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0

    account_id = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.environ.get("CLOUDFLARE_ANALYTICS_TOKEN", "").strip()
    worker = os.environ.get("WORKER_NAME", "kdkmp-development-pilot").strip()
    base = os.environ.get("PILOT_URL", "").strip()
    if not all((account_id, token, worker, base)):
        raise SystemExit("route_isolation_gate=BLOCKED_REQUIRED_ENV_MISSING")

    module = load_analytics_module()
    unit, descriptions = module.query_cpu_unit(token)
    if unit == "unknown":
        raise SystemExit("route_isolation_gate=BLOCKED_CPU_UNIT_UNVERIFIED")
    print(f"route_isolation_cpu_unit={unit}", flush=True)
    print(f"route_isolation_schema_description_count={len(descriptions)}", flush=True)
    print("route_isolation_mode=PUBLIC_GET_PLUS_READ_ONLY_GRAPHQL", flush=True)
    print("route_isolation_evidence_class=DIAGNOSTIC_ONLY_ADAPTIVE_DATASET", flush=True)
    print(f"route_isolation_min_coverage_ratio={MIN_COVERAGE_RATIO:.2f}", flush=True)

    batches: list[Batch] = []
    for index, (label, path, expected) in enumerate(ROUTES):
        batches.append(run_batch(base, label, path, expected))
        if index < len(ROUTES) - 1:
            time.sleep(BETWEEN_BATCH_SECONDS)

    print(f"route_isolation_ingestion_buffer_seconds={INITIAL_INGESTION_WAIT_SECONDS}", flush=True)
    time.sleep(INITIAL_INGESTION_WAIT_SECONDS)

    required_observed = minimum_observed_requests()
    pending = {batch.label: batch for batch in batches}
    results = {}
    for poll in range(1, MAX_POLLS + 1):
        for label, batch in list(pending.items()):
            summary = query_batch(module, account_id, token, worker, batch)
            observed = int(summary["requests"])
            coverage = observed / SAMPLE_SIZE
            print(
                f"route_isolation_observed poll={poll} label={label} requests={observed} "
                f"coverage={coverage:.3f}",
                flush=True,
            )
            if observed >= required_observed:
                results[label] = summary
                del pending[label]
        if not pending:
            break
        print(f"route_isolation_poll={poll} pending={','.join(sorted(pending))}", flush=True)
        if poll < MAX_POLLS:
            time.sleep(POLL_SECONDS)

    if pending:
        print("route_isolation_gate=INSUFFICIENT_ADAPTIVE_COVERAGE")
        print("route_isolation_pending=" + ",".join(sorted(pending)))
        return 2

    any_fail = False
    for batch in batches:
        summary = results[batch.label]
        gate, p50_ms, p99_ms = classify_route(module, summary, unit)
        observed = int(summary["requests"])
        coverage = observed / SAMPLE_SIZE
        contamination = max(0, observed - SAMPLE_SIZE)
        p50 = "none" if p50_ms is None else f"{p50_ms:.6f}"
        p99 = "none" if p99_ms is None else f"{p99_ms:.6f}"
        print(
            f"route_cpu label={batch.label} path={batch.path} sent={SAMPLE_SIZE} "
            f"observed={observed} coverage={coverage:.3f} extra_requests={contamination} "
            f"errors={summary['errors']} exceeded={summary['exceeded_resource_requests']} "
            f"p50_ms={p50} p99_ms={p99} gate={gate} evidence=DIAGNOSTIC_ONLY",
            flush=True,
        )
        if gate.startswith("FAIL_"):
            any_fail = True

    print("cloudflare_resource_write_attempted=false")
    print("database_write_attempted=false")
    print("production_data_used=false")
    print("r2_activated=false")
    print("route_isolation_gate=" + ("CPU_HOTSPOT_IDENTIFIED" if any_fail else "NO_MEDIAN_CPU_FAILURE_IN_ISOLATED_ROUTES"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
