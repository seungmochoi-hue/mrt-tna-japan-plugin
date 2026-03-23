# /// script
# requires-python = ">=3.12"
# dependencies = ["requests"]
# ///
"""Redash API wrapper for Claude Code agent.

Usage:
    uv run .claude/scripts/redash-api.py get-query <query_id_or_url>
    uv run .claude/scripts/redash-api.py check-query <query_id_or_url> [--max-age=3600] [--sample-rows=20] [--timeout=180] [--parameters='{"name":"value"}']
    uv run .claude/scripts/redash-api.py get-dashboard <slug_or_id>

API Key is read from .claude/credentials/redash.env (REDASH_API_KEY=xxx).
"""
import json
import os
import re
import sys
import time
from urllib.parse import parse_qs, urlparse

import requests

REDASH_BASE_URL = "https://redash.myrealtrip.net"
CREDENTIALS_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "credentials",
    "redash.env",
)

QUERY_ID_RE = re.compile(r"/queries/(?P<id>\d+)", re.IGNORECASE)

TABLE_REF_RE = re.compile(
    r"(?:FROM|JOIN)\s+`?([\w-]+(?:\.[\w-]+){0,2})`?",
    re.IGNORECASE,
)

EXCLUDE_TABLES = {"UNNEST", "LATERAL", "GENERATE_SERIES", "DUAL"}


def load_api_key() -> str:
    path = os.environ.get("REDASH_CREDENTIALS_PATH", CREDENTIALS_PATH)
    if not os.path.exists(path):
        print(
            json.dumps(
                {
                    "error": "API_KEY_NOT_FOUND",
                    "message": f"Redash API Key 파일이 없습니다: {path}",
                    "hint": "사용자에게 Redash API Key를 요청하고 .claude/credentials/redash.env 에 저장하세요.",
                }
            )
        )
        sys.exit(1)

    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip().lstrip("export").strip()
            value = value.strip().strip("\"'")
            if key.upper() in (
                "REDASH_API_KEY",
                "REDASH_KEY",
                "REDASH_TOKEN",
                "REDASH_API_TOKEN",
            ):
                return value

    print(
        json.dumps(
            {
                "error": "API_KEY_EMPTY",
                "message": f"REDASH_API_KEY가 파일에 없습니다: {path}",
            }
        )
    )
    sys.exit(1)


def parse_json_or_text(response: requests.Response):
    try:
        return response.json()
    except ValueError:
        return response.text


def parse_query_input(query_id_or_url: str) -> tuple[int, dict]:
    s = query_id_or_url.strip()
    if s.isdigit():
        return int(s), {}

    parsed = urlparse(s)
    query_params = {}
    if parsed.scheme and parsed.netloc:
        query_params = {
            key.removeprefix("p_"): values[0]
            for key, values in parse_qs(parsed.query).items()
            if values and key.startswith("p_")
        }

    m = QUERY_ID_RE.search(s)
    if m:
        return int(m.group("id")), query_params
    raise ValueError(f"Redash 쿼리 ID를 추출할 수 없습니다: {s}")


def extract_tables(sql: str) -> list[str]:
    cleaned = re.sub(r"--[^\n]*", "", sql)
    cleaned = re.sub(r"/\*.*?\*/", "", cleaned, flags=re.DOTALL)
    tables = set()
    for m in TABLE_REF_RE.findall(cleaned):
        name = m.strip("`").strip()
        if not name or name.upper() in EXCLUDE_TABLES or name.isdigit() or len(name) <= 1:
            continue
        tables.add(name)
    return sorted(tables)


def api_get(path: str, api_key: str, timeout: int = 30) -> dict:
    url = f"{REDASH_BASE_URL}{path}"
    r = requests.get(url, headers={"Authorization": f"Key {api_key}"}, timeout=timeout)
    return {"status_code": r.status_code, "data": parse_json_or_text(r) if r.ok else None, "error": parse_json_or_text(r) if not r.ok else None}


def api_post(path: str, api_key: str, payload: dict, timeout: int = 60) -> dict:
    url = f"{REDASH_BASE_URL}{path}"
    r = requests.post(
        url,
        headers={"Authorization": f"Key {api_key}", "Content-Type": "application/json"},
        json=payload,
        timeout=timeout,
    )
    return {"status_code": r.status_code, "data": parse_json_or_text(r) if r.ok else None, "error": parse_json_or_text(r) if not r.ok else None}


def normalize_parameter_value(value):
    if isinstance(value, dict):
        for key in ("value", "name", "id"):
            candidate = value.get(key)
            if candidate not in (None, ""):
                return candidate
        return value
    if isinstance(value, list):
        return [normalize_parameter_value(item) for item in value]
    return value


def extract_parameter_value(parameter: dict):
    for key in ("value", "default", "defaultValue"):
        if key not in parameter:
            continue
        value = normalize_parameter_value(parameter.get(key))
        if value not in (None, "", []):
            return value
    return None


def build_execution_parameters(query_parameters: list[dict], url_parameters: dict, cli_parameters: dict) -> dict:
    explicit = {**url_parameters, **cli_parameters}
    resolved = {}

    for parameter in query_parameters:
        name = parameter.get("name")
        if not name:
            continue
        if name in explicit:
            resolved[name] = explicit[name]
            continue
        default_value = extract_parameter_value(parameter)
        if default_value not in (None, "", []):
            resolved[name] = default_value

    for key, value in explicit.items():
        if value not in (None, "", []):
            resolved[key] = value

    return resolved


# ── Commands ──────────────────────────────────────────────


def cmd_get_query(args: list[str]) -> None:
    if not args:
        print(json.dumps({"error": "query_id_or_url 인자가 필요합니다."}))
        sys.exit(1)

    api_key = load_api_key()
    qid, _ = parse_query_input(args[0])
    resp = api_get(f"/api/queries/{qid}", api_key)

    if resp["data"]:
        q = resp["data"]
        sql = q.get("query", "")
        result = {
            "query_id": q.get("id"),
            "name": q.get("name"),
            "description": q.get("description"),
            "data_source_id": q.get("data_source_id"),
            "schedule": q.get("schedule"),
            "sql": sql,
            "tables": extract_tables(sql),
            "parameters": [
                {"name": p.get("name"), "type": p.get("type"), "value": p.get("value")}
                for p in (q.get("options", {}).get("parameters") or [])
            ],
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(resp, ensure_ascii=False, indent=2))


def cmd_check_query(args: list[str]) -> None:
    if not args:
        print(json.dumps({"error": "query_id_or_url 인자가 필요합니다."}))
        sys.exit(1)

    max_age = 3600
    sample_rows = 20
    timeout_sec = 180
    cli_parameters = {}
    for a in args[1:]:
        if a.startswith("--max-age="):
            max_age = int(a.split("=", 1)[1])
        elif a.startswith("--sample-rows="):
            sample_rows = int(a.split("=", 1)[1])
        elif a.startswith("--timeout="):
            timeout_sec = int(a.split("=", 1)[1])
        elif a.startswith("--parameters="):
            cli_parameters = json.loads(a.split("=", 1)[1])

    api_key = load_api_key()
    qid, url_parameters = parse_query_input(args[0])

    # 1. Query definition
    q_resp = api_get(f"/api/queries/{qid}", api_key)
    result: dict = {"query_id": qid}
    query_parameters = []
    if q_resp["data"]:
        q = q_resp["data"]
        result["name"] = q.get("name")
        result["sql"] = q.get("query", "")
        result["tables"] = extract_tables(result["sql"])
        query_parameters = q.get("options", {}).get("parameters") or []
    else:
        result["query_error"] = q_resp

    # 2. Trigger execution
    execution_parameters = build_execution_parameters(query_parameters, url_parameters, cli_parameters)
    if execution_parameters:
        result["execution_parameters"] = execution_parameters

    run_resp = api_post(
        f"/api/queries/{qid}/results",
        api_key,
        {"max_age": max_age, "parameters": execution_parameters},
    )
    if not run_resp["data"]:
        result["execution_error"] = run_resp
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    run_data = run_resp["data"]

    # Direct result (cached)
    qr = run_data.get("query_result")
    if isinstance(qr, dict) and qr.get("id"):
        rows = (qr.get("data") or {}).get("rows") or []
        result["total_rows"] = len(rows)
        result["sample_rows"] = rows[:sample_rows]
        result["cached"] = True
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    # Job polling
    job = run_data.get("job") or {}
    job_id = job.get("id") or run_data.get("job_id")
    if not job_id:
        result["execution_error"] = "No job_id in response"
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        j_resp = api_get(f"/api/jobs/{job_id}", api_key)
        if not j_resp["data"]:
            time.sleep(2)
            continue
        j = (j_resp["data"].get("job") or j_resp["data"])
        status = j.get("status")
        if status in (3, 4) or str(status).lower() in ("done", "failed"):
            qrid = j.get("query_result_id") or j.get("result_id")
            if not qrid:
                result["job_error"] = j.get("error") or "No query_result_id"
                print(json.dumps(result, ensure_ascii=False, indent=2))
                return
            # Fetch result
            r_resp = api_get(f"/api/query_results/{qrid}", api_key)
            if r_resp["data"]:
                rows = ((r_resp["data"].get("query_result") or {}).get("data") or {}).get("rows") or []
                result["total_rows"] = len(rows)
                result["sample_rows"] = rows[:sample_rows]
                result["cached"] = False
            else:
                result["result_error"] = r_resp
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return
        time.sleep(2)

    result["timeout"] = f"Job {job_id} did not complete within {timeout_sec}s"
    print(json.dumps(result, ensure_ascii=False, indent=2))


def cmd_get_dashboard(args: list[str]) -> None:
    if not args:
        print(json.dumps({"error": "slug_or_id 인자가 필요합니다."}))
        sys.exit(1)

    slug = args[0].strip()
    # Extract slug from URL if full URL given
    m = re.search(r"/dashboard/([^/?#]+)", slug)
    if m:
        slug = m.group(1)

    api_key = load_api_key()
    resp = api_get(f"/api/dashboards/{slug}", api_key)

    if not resp["data"]:
        print(json.dumps(resp, ensure_ascii=False, indent=2))
        return

    dash = resp["data"]
    queries = []
    seen = set()
    for w in dash.get("widgets") or []:
        vis = w.get("visualization")
        if not vis:
            continue
        q = vis.get("query")
        if not q:
            continue
        qid = q.get("id")
        if qid in seen:
            continue
        seen.add(qid)
        sql = q.get("query", "")
        queries.append({
            "query_id": qid,
            "query_name": q.get("name"),
            "sql": sql,
            "tables": extract_tables(sql),
        })

    result = {
        "dashboard_id": dash.get("id"),
        "dashboard_name": dash.get("name"),
        "dashboard_slug": dash.get("slug"),
        "query_count": len(queries),
        "queries": queries,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


# ── Main ──────────────────────────────────────────────────

COMMANDS = {
    "get-query": cmd_get_query,
    "check-query": cmd_check_query,
    "get-dashboard": cmd_get_dashboard,
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(f"Usage: {sys.argv[0]} <{'|'.join(COMMANDS)}> <args...>")
        sys.exit(1)
    COMMANDS[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
