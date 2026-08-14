#!/usr/bin/env python3
"""Read-only Cloudflare Workers analytics probe for the DEVELOPMENT pilot.

This script never creates, updates, or deletes Cloudflare resources. It reads
workersInvocationsAdaptive through Cloudflare's GraphQL Analytics API, uses
GraphQL introspection to verify the CPU quantile unit from Cloudflare's live
schema, and emits sanitized key=value evidence suitable for GitHub Actions logs.
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
FREE_CPU_LIMIT_MS = 10.0

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
          scriptName
          status
        }
      }
    }
  }
}
""".strip()

INTROSPECTION_QUERY = r"""
query IntrospectWorkerCpuQuantiles {
  __schema {
    types {
      name
      fields(includeDeprecated: true) {
        name
        description
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


def _raise_graphql_errors(payload: dict[str, Any]) -> None:
    errors = payload.get("errors")
    if not errors:
        return
    messages = []
    for item in errors if isinstance(errors, list) else [errors]:
        if isinstance(item, dict):
            messages.append(str(item.get("message", "GraphQL error")))
        else:
            messages.append(str(item))
    raise AnalyticsError("GraphQL returned errors: " + " | ".join(messages[:3]))


def summarize(payload: dict[str, Any]) -> dict[str, Any]:
    _raise_graphql_errors(payload)

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
        "cpu_time_p50_raw_max_across_status_groups": max(p50_values) if p50_values else None,
        "cpu_time_p99_raw_max_across_status_groups": max(p99_values) if p99_values else None,
        "analytics_gate": gate,
    }


def detect_cpu_unit(payload: dict[str, Any]) -> tuple[str, list[str]]:
    """Return a verified unit from Cloudflare schema field descriptions.

    The detector intentionally refuses to infer a unit from field names or numeric
    magnitudes. It accepts a unit only when the live GraphQL schema description for
    workersInvocationsAdaptive CPU quantiles states it explicitly.
    """

    _raise_graphql_errors(payload)
    try:
        types = payload["data"]["__schema"]["types"]
    except (KeyError, TypeError) as exc:
        raise AnalyticsError("GraphQL introspection did not contain __schema.types") from exc

    descriptions: list[str] = []
    matched_fields: set[str] = set()
    for type_info in types or []:
        type_name = str((type_info or {}).get("name") or "")
        normalized_type = "".join(ch.lower() for ch in type_name if ch.isalnum())
        if "workersinvocationsadaptive" not in normalized_type:
            continue
        for field in (type_info or {}).get("fields") or []:
            field_name = str((field or {}).get("name") or "")
            if field_name not in {"cpuTimeP50", "cpuTimeP99"}:
                continue
            matched_fields.add(field_name)
            description = str((field or {}).get("description") or "").strip()
            if description:
                descriptions.append(description)

    if matched_fields != {"cpuTimeP50", "cpuTimeP99"} or not descriptions:
        return "unknown", descriptions

    combined = " ".join(descriptions).lower()
    if "microsecond" in combined:
        return "microseconds", descriptions
    if "millisecond" in combined:
        return "milliseconds", descriptions
    if "nanosecond" in combined:
        return "nanoseconds", descriptions
    if " second" in combined or combined.startswith("second"):
        return "seconds", descriptions
    return "unknown", descriptions


def _to_ms(value: float | None, unit: str) -> float | None:
    if value is None:
        return None
    if unit == "microseconds":
        return value / 1000.0
    if unit == "milliseconds":
        return value
    if unit == "nanoseconds":
        return value / 1_000_000.0
    if unit == "seconds":
        return value * 1000.0
    return None


def evaluate_cpu_budget(summary: dict[str, Any], unit: str) -> dict[str, Any]:
    p50_ms = _to_ms(summary["cpu_time_p50_raw_max_across_status_groups"], unit)
    p99_ms = _to_ms(summary["cpu_time_p99_raw_max_across_status_groups"], unit)

    if summary["analytics_gate"] == "FAIL_RUNTIME_ERRORS":
        gate = "FAIL_RUNTIME_ERRORS"
    elif summary["analytics_gate"] not in {"MEASUREMENT_COLLECTED"}:
        gate = "NOT_EVALUATED_INSUFFICIENT_ANALYTICS"
    elif unit == "unknown" or p50_ms is None or p99_ms is None:
        gate = "BLOCKED_UNIT_UNVERIFIED"
    elif summary["exceeded_resource_requests"] > 0:
        gate = "FAIL_EXCEEDED_RESOURCES"
    elif p50_ms > FREE_CPU_LIMIT_MS:
        gate = "FAIL_MEDIAN_OVER_FREE_10MS"
    elif p99_ms > FREE_CPU_LIMIT_MS:
        gate = "CONDITIONAL_P99_OVER_FREE_10MS"
    else:
        gate = "PASS_WITHIN_FREE_10MS"

    return {
        "p50_ms": p50_ms,
        "p99_ms": p99_ms,
        "gate": gate,
    }


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _post_graphql(token: str, query: str, variables: dict[str, Any] | None = None) -> dict[str, Any]:
    body = json.dumps({"query": query, "variables": variables or {}}).encode("utf-8")
    request = urllib.request.Request(
        GRAPHQL_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "kdkmp-zc5j-readonly-analytics/1.0",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise AnalyticsError(f"Cloudflare analytics HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise AnalyticsError(f"Cloudflare analytics request failed: {exc.reason}") from exc

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise AnalyticsError("Cloudflare analytics response was not valid JSON") from exc


def query_cloudflare(account_id: str, token: str, worker: str, lookback_hours: int) -> dict[str, Any]:
    end = datetime.now(timezone.utc)
    start = end - timedelta(hours=lookback_hours)
    return _post_graphql(
        token,
        QUERY,
        {
            "accountTag": account_id,
            "datetimeStart": _iso(start),
            "datetimeEnd": _iso(end),
            "scriptName": worker,
        },
    )


def query_cpu_unit(token: str) -> tuple[str, list[str]]:
    return detect_cpu_unit(_post_graphql(token, INTROSPECTION_QUERY))


def emit(summary: dict[str, Any], worker: str, lookback_hours: int, unit: str, cpu: dict[str, Any]) -> None:
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
        "cpu_time_p50_raw_max_across_status_groups="
        + ("none" if summary["cpu_time_p50_raw_max_across_status_groups"] is None else str(summary["cpu_time_p50_raw_max_across_status_groups"]))
    )
    print(
        "cpu_time_p99_raw_max_across_status_groups="
        + ("none" if summary["cpu_time_p99_raw_max_across_status_groups"] is None else str(summary["cpu_time_p99_raw_max_across_status_groups"]))
    )
    print(f"cpu_quantile_unit_verified={unit}")
    print("cpu_free_limit_ms=10")
    print("cpu_time_p50_ms=" + ("none" if cpu["p50_ms"] is None else f"{cpu['p50_ms']:.6f}"))
    print("cpu_time_p99_ms=" + ("none" if cpu["p99_ms"] is None else f"{cpu['p99_ms']:.6f}"))
    print(f"cpu_free_10ms_gate={cpu['gate']}")
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
                                "sum": {"requests": 12, "errors": 0, "subrequests": 12},
                            }
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
    assert result["cpu_time_p50_raw_max_across_status_groups"] == 206
    assert result["cpu_time_p99_raw_max_across_status_groups"] == 291
    assert result["analytics_gate"] == "MEASUREMENT_COLLECTED"

    schema_fixture = {
        "data": {
            "__schema": {
                "types": [
                    {
                        "name": "AccountWorkersInvocationsAdaptiveQuantiles",
                        "fields": [
                            {"name": "cpuTimeP50", "description": "CPU time 50th percentile - microseconds"},
                            {"name": "cpuTimeP99", "description": "CPU time 99th percentile - microseconds"},
                        ],
                    }
                ]
            }
        },
        "errors": None,
    }
    unit, _ = detect_cpu_unit(schema_fixture)
    assert unit == "microseconds"
    cpu = evaluate_cpu_budget(result, unit)
    assert abs(cpu["p50_ms"] - 0.206) < 1e-9
    assert abs(cpu["p99_ms"] - 0.291) < 1e-9
    assert cpu["gate"] == "PASS_WITHIN_FREE_10MS"

    conditional = json.loads(json.dumps(fixture))
    conditional["data"]["viewer"]["accounts"][0]["workersInvocationsAdaptive"][0]["quantiles"] = {
        "cpuTimeP50": 5000,
        "cpuTimeP99": 15000,
    }
    conditional_cpu = evaluate_cpu_budget(summarize(conditional), unit)
    assert conditional_cpu["gate"] == "CONDITIONAL_P99_OVER_FREE_10MS"

    exceeded = json.loads(json.dumps(fixture))
    exceeded["data"]["viewer"]["accounts"][0]["workersInvocationsAdaptive"][0]["dimensions"]["status"] = "exceededResources"
    exceeded_result = summarize(exceeded)
    assert exceeded_result["analytics_gate"] == "FAIL_RUNTIME_ERRORS"
    assert evaluate_cpu_budget(exceeded_result, unit)["gate"] == "FAIL_RUNTIME_ERRORS"
    print("zc5j_self_test=PASS")


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
        unit, descriptions = query_cpu_unit(token)
        cpu = evaluate_cpu_budget(summary, unit)
    except AnalyticsError as exc:
        print(f"analytics_error={str(exc)[:700]}", file=sys.stderr)
        print("analytics_gate=BLOCKED_QUERY_FAILED")
        return 3

    print(f"cpu_schema_description_count={len(descriptions)}")
    emit(summary, worker, lookback_hours, unit, cpu)

    if summary["analytics_gate"] == "FAIL_RUNTIME_ERRORS" or cpu["gate"].startswith("FAIL_"):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
