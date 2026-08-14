#!/usr/bin/env python3
"""Read-only Cloudflare Workers analytics probe for the DEVELOPMENT pilot.

This script never creates, updates, or deletes Cloudflare resources. It reads
workersInvocationsAdaptive through Cloudflare's GraphQL Analytics API and emits
sanitized key=value evidence suitable for GitHub Actions logs.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any

GRAPHQL_URL = "https://api.cloudflare.com/client/v4/graphql"
DEFAULT_WORKER = "kdkmp-development-pilot"
DEFAULT_LOOKBACK_HOURS = 24

QUERY = r"""
query GetWorkersAnalytics(
  $accountTag: string,
  $datetimeStart: string,
  $datetimeEnd: string,
  $scriptName: string
) {
  viewer {
    accounts(filter: {accountTag: $accountTag}) {
      workersInvocationsAdaptive(
        limit: 1000,
        filter: {
          scriptName: $scriptName,
          datetime_geq: $datetimeStart,
          datetime_leq: $datetimeEnd
        }
      ) {
        sum {
          subrequests
          requests
          errors
        }
        quantiles {
          cpuTimeP50
          cpuTimeP99
        }
        dimensions {
          datetime
          scriptName
          status
        }
      }
    }
  }
}
""".strip()


class AnalyticsError(RuntimeError):
    pass


def _number(value: Any) -> float:
    if value is None:
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise AnalyticsError(f"Unexpected numeric value: {value!r}") from exc


def summarize(payload: dict[str, Any]) -> dict[str, Any]:
    errors = payload.get("errors")
    if errors:
        messages = []
        for item in errors if isinstance(errors, list) else [errors]:
            if isinstance(item, dict):
                messages.append(str(item.get("message", "GraphQL error")))
            else:
                messages.append(str(item))
        raise AnalyticsError("GraphQL returned errors: " + " | ".join(messages[:3]))

    try:
        accounts = payload["data"]["viewer"]["accounts"]
    except (KeyError, TypeError) as exc:
        raise AnalyticsError("GraphQL response did not contain viewer.accounts") from exc

    if not accounts:
        raise AnalyticsError("Cloudflare account was not returned by the analytics query")

    rows = accounts[0].get("workersInvocationsAdaptive") or []
    total_requests = 0
    total_errors = 0
    total_subrequests = 0
    exceeded_resource_requests = 0
    statuses: set[str] = set()
    p50_values: list[float] = []
    p99_values: list[float] = []

    for row in rows:
        sums = row.get("sum") or {}
        requests = int(_number(sums.get("requests")))
        total_requests += requests
        total_errors += int(_number(sums.get("errors")))
        total_subrequests += int(_number(sums.get("subrequests")))

        dimensions = row.get("dimensions") or {}
        status = str(dimensions.get("status") or "unknown")
        statuses.add(status)
        if status.lower() == "exceededresources":
            exceeded_resource_requests += requests

        quantiles = row.get("quantiles") or {}
        if quantiles.get("cpuTimeP50") is not None:
            p50_values.append(_number(quantiles.get("cpuTimeP50")))
        if quantiles.get("cpuTimeP99") is not None:
            p99_values.append(_number(quantiles.get("cpuTimeP99")))

    if total_requests == 0:
        gate = "INSUFFICIENT_DATA"
    elif exceeded_resource_requests > 0 or total_errors > 0:
        gate = "FAIL_RUNTIME_ERRORS"
    elif total_requests < 10:
        gate = "INSUFFICIENT_SAMPLE"
    else:
        gate = "MEASUREMENT_COLLECTED"

    return {
        "row_count": len(rows),
        "requests": total_requests,
        "errors": total_errors,
        "subrequests": total_subrequests,
        "exceeded_resource_requests": exceeded_resource_requests,
        "statuses": ",".join(sorted(statuses)) if statuses else "none",
        "cpu_time_p50_raw_max_across_groups": max(p50_values) if p50_values else None,
        "cpu_time_p99_raw_max_across_groups": max(p99_values) if p99_values else None,
        "analytics_gate": gate,
    }


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def query_cloudflare(account_id: str, token: str, worker: str, lookback_hours: int) -> dict[str, Any]:
    end = datetime.now(timezone.utc)
    start = end - timedelta(hours=lookback_hours)
    body = json.dumps(
        {
            "query": QUERY,
            "variables": {
                "accountTag": account_id,
                "datetimeStart": _iso(start),
                "datetimeEnd": _iso(end),
                "scriptName": worker,
            },
        }
    ).encode("utf-8")

    request = urllib.request.Request(
        GRAPHQL_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "kdkmp-zc5h-readonly-analytics/1.0",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        # Never echo headers or the bearer token. A short response message is safe
        # enough for diagnosis while keeping credentials out of logs.
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise AnalyticsError(f"Cloudflare analytics HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise AnalyticsError(f"Cloudflare analytics request failed: {exc.reason}") from exc

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise AnalyticsError("Cloudflare analytics response was not valid JSON") from exc


def emit(summary: dict[str, Any], worker: str, lookback_hours: int) -> None:
    print(f"analytics_worker={worker}")
    print(f"analytics_lookback_hours={lookback_hours}")
    print("analytics_mode=READ_ONLY")
    print(f"analytics_row_count={summary['row_count']}")
    print(f"analytics_requests={summary['requests']}")
    print(f"analytics_errors={summary['errors']}")
    print(f"analytics_subrequests={summary['subrequests']}")
    print(f"analytics_exceeded_resource_requests={summary['exceeded_resource_requests']}")
    print(f"analytics_statuses={summary['statuses']}")
    print(
        "cpu_time_p50_raw_max_across_groups="
        + ("none" if summary["cpu_time_p50_raw_max_across_groups"] is None else str(summary["cpu_time_p50_raw_max_across_groups"]))
    )
    print(
        "cpu_time_p99_raw_max_across_groups="
        + ("none" if summary["cpu_time_p99_raw_max_across_groups"] is None else str(summary["cpu_time_p99_raw_max_across_groups"]))
    )
    print("cpu_quantile_unit=cloudflare_graphql_native_not_assumed")
    print("cpu_10ms_threshold_decision=NOT_AUTOMATED_UNTIL_UNIT_IS_VERIFIED")
    print(f"analytics_gate={summary['analytics_gate']}")


def self_test() -> None:
    fixture = {
        "data": {
            "viewer": {
                "accounts": [
                    {
                        "workersInvocationsAdaptive": [
                            {
                                "dimensions": {"status": "success"},
                                "quantiles": {"cpuTimeP50": 206, "cpuTimeP99": 291},
                                "sum": {"requests": 7, "errors": 0, "subrequests": 7},
                            },
                            {
                                "dimensions": {"status": "success"},
                                "quantiles": {"cpuTimeP50": 180, "cpuTimeP99": 250.5},
                                "sum": {"requests": 5, "errors": 0, "subrequests": 5},
                            },
                        ]
                    }
                ]
            }
        },
        "errors": None,
    }
    result = summarize(fixture)
    assert result["requests"] == 12
    assert result["errors"] == 0
    assert result["cpu_time_p50_raw_max_across_groups"] == 206
    assert result["cpu_time_p99_raw_max_across_groups"] == 291
    assert result["analytics_gate"] == "MEASUREMENT_COLLECTED"

    exceeded = json.loads(json.dumps(fixture))
    exceeded["data"]["viewer"]["accounts"][0]["workersInvocationsAdaptive"][1]["dimensions"]["status"] = "exceededResources"
    assert summarize(exceeded)["analytics_gate"] == "FAIL_RUNTIME_ERRORS"
    print("zc5h_self_test=PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0

    account_id = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.environ.get("CLOUDFLARE_ANALYTICS_TOKEN", "").strip()
    worker = os.environ.get("WORKER_NAME", DEFAULT_WORKER).strip() or DEFAULT_WORKER
    lookback_raw = os.environ.get("ANALYTICS_LOOKBACK_HOURS", str(DEFAULT_LOOKBACK_HOURS)).strip()

    try:
        lookback_hours = max(1, min(168, int(lookback_raw)))
    except ValueError:
        print("analytics_gate=BLOCKED_INVALID_LOOKBACK")
        return 2

    if not token:
        print("analytics_secret_present=false")
        print("analytics_gate=BLOCKED_SECRET_MISSING")
        return 0

    print("analytics_secret_present=true")
    if not account_id:
        print("analytics_gate=BLOCKED_ACCOUNT_ID_MISSING")
        return 2

    try:
        payload = query_cloudflare(account_id, token, worker, lookback_hours)
        summary = summarize(payload)
    except AnalyticsError as exc:
        # The error never contains request headers/token. Keep the output bounded.
        print(f"analytics_error={str(exc)[:700]}", file=sys.stderr)
        print("analytics_gate=BLOCKED_QUERY_FAILED")
        return 3

    emit(summary, worker, lookback_hours)
    return 1 if summary["analytics_gate"] == "FAIL_RUNTIME_ERRORS" else 0


if __name__ == "__main__":
    raise SystemExit(main())
