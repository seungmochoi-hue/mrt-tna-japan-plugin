#!/bin/bash
# bq query guard
# exit 0 = allow, exit 2 = block

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
QUERY_TARGET="$COMMAND"
ARGV_COUNT=$(echo "$INPUT" | jq -r '(.tool_input.argv // []) | length')

if [ "${ARGV_COUNT:-0}" -ge 3 ]; then
  ARG0=$(echo "$INPUT" | jq -r '.tool_input.argv[0] // empty')
  ARG1=$(echo "$INPUT" | jq -r '.tool_input.argv[1] // empty')
  LAST_ARG=$(echo "$INPUT" | jq -r '.tool_input.argv[-1] // empty')
  LAST_ARG_UPPER=$(printf '%s' "$LAST_ARG" | tr '[:lower:]' '[:upper:]')

  if [ "$ARG0" = "bq" ] && [ "$ARG1" = "query" ] && {
    printf '%s' "$LAST_ARG" | grep -q '[[:space:]]' ||
    printf '%s' "$LAST_ARG_UPPER" | grep -qE '^[[:space:]]*(SELECT|WITH|DECLARE|EXPLAIN|#STANDARDSQL)\b'
  }; then
    QUERY_TARGET="$LAST_ARG"
  fi
fi

# Only guard commands that start with bq
if ! echo "$COMMAND" | grep -qE '^[[:space:]]*bq[[:space:]]'; then
  exit 0
fi

# Allow-list
if echo "$COMMAND" | grep -qE '^[[:space:]]*bq[[:space:]]+(show|ls|head|version)([[:space:]]|$)'; then
  exit 0
fi

if ! echo "$COMMAND" | grep -qE '^[[:space:]]*bq[[:space:]]+query([[:space:]]|$)'; then
  echo "BLOCKED: bq는 query / show / ls / head / version 명령만 허용됩니다." >&2
  exit 2
fi

# --location 플래그 필수 검증
if ! echo "$COMMAND" | grep -qE -- '--location(=|[[:space:]]+)asia-northeast3([[:space:]]|$)'; then
  echo "BLOCKED: --location=asia-northeast3 플래그가 필요합니다." >&2
  exit 2
fi

UPPER_COMMAND=$(printf '%s' "$COMMAND" | tr '[:lower:]' '[:upper:]')

contains_dw_biz_log_reference() {
  printf '%s' "$UPPER_COMMAND" | grep -qE '(^|[^A-Z0-9_])DW_BIZ_LOG([^A-Z0-9_]|$)'
}

resolve_python_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' python3
    return 0
  fi

  if command -v python >/dev/null 2>&1; then
    printf '%s' python
    return 0
  fi

  return 1
}

validate_dw_biz_log_window() {
  local validation_output
  local python_cmd

  if ! python_cmd=$(resolve_python_cmd); then
    echo "BLOCKED: DW_BIZ_LOG 기간 제한 검증에 python 또는 python3가 필요합니다." >&2
    return 1
  fi

  if ! validation_output=$(
    COMMAND_ENV="$COMMAND" QUERY_ENV="$QUERY_TARGET" "$python_cmd" - <<'PY'
import os
import re
import sys
from datetime import date, timedelta

cmd = os.environ["COMMAND_ENV"]
sql = os.environ.get("QUERY_ENV") or cmd
sql = re.sub(r'(?m)--[^\n]*$', '', sql)
sql = re.sub(r'/\*.*?\*/', '', sql, flags=re.DOTALL)
normalized = " ".join(sql.upper().split())

if not re.search(r"(^|[^A-Z0-9_])DW_BIZ_LOG([^A-Z0-9_]|$)", normalized):
    sys.exit(0)

current_date_expr = r"CURRENT_DATE(?:\([^)]*\))?"
date_literal = r"(?:DATE\s*)?['\"](\d{4}-\d{2}-\d{2})['\"]"


def fail(message: str) -> None:
    print(
        "BLOCKED: DW_BIZ_LOG 조회는 basis_dt 기준 최대 7일 범위만 허용됩니다. "
        + message
    )
    sys.exit(1)


def ensure_max_7_days(span_days: int) -> None:
    if span_days < 1:
        fail("시작일과 종료일이 올바른지 확인하세요.")
    if span_days > 7:
        fail("basis_dt 범위를 7일 이하로 줄여주세요.")
    sys.exit(0)


def explicit_span(lower_date: str, lower_op: str, upper_date: str, upper_op: str) -> int:
    lower = date.fromisoformat(lower_date)
    upper = date.fromisoformat(upper_date)
    if lower_op == ">":
        lower += timedelta(days=1)
    if upper_op == "<":
        upper -= timedelta(days=1)
    return (upper - lower).days + 1


def relative_span(lower_interval: int, lower_op: str, upper_interval: int, upper_op: str) -> int:
    first_offset = lower_interval - (1 if lower_op == ">" else 0)
    last_offset = upper_interval + (1 if upper_op == "<" else 0)
    return first_offset - last_offset + 1


if "BASIS_DT" not in normalized:
    fail("basis_dt 조건이 필요합니다.")

if re.search(rf"\bBASIS_DT\s*=\s*{date_literal}", normalized):
    sys.exit(0)

match = re.search(
    rf"\bBASIS_DT\s+BETWEEN\s+{date_literal}\s+AND\s+{date_literal}",
    normalized,
)
if match:
    ensure_max_7_days(explicit_span(match.group(1), ">=", match.group(2), "<="))

lower_explicit = re.search(rf"\bBASIS_DT\s*(>=|>)\s*{date_literal}", normalized)
upper_explicit = re.search(rf"\bBASIS_DT\s*(<=|<)\s*{date_literal}", normalized)
if lower_explicit and upper_explicit:
    ensure_max_7_days(
        explicit_span(
            lower_explicit.group(2),
            lower_explicit.group(1),
            upper_explicit.group(2),
            upper_explicit.group(1),
        )
    )

match = re.search(
    rf"\bBASIS_DT\s+BETWEEN\s+DATE_SUB\(\s*{current_date_expr}\s*,\s*INTERVAL\s*(\d+)\s+DAY\s*\)\s+AND\s+DATE_SUB\(\s*{current_date_expr}\s*,\s*INTERVAL\s*(\d+)\s+DAY\s*\)",
    normalized,
)
if match:
    ensure_max_7_days(relative_span(int(match.group(1)), ">=", int(match.group(2)), "<="))

lower_relative = re.search(
    rf"\bBASIS_DT\s*(>=|>)\s*DATE_SUB\(\s*{current_date_expr}\s*,\s*INTERVAL\s*(\d+)\s+DAY\s*\)",
    normalized,
)
upper_relative_sub = re.search(
    rf"\bBASIS_DT\s*(<=|<)\s*DATE_SUB\(\s*{current_date_expr}\s*,\s*INTERVAL\s*(\d+)\s+DAY\s*\)",
    normalized,
)
upper_relative_now = re.search(
    rf"\bBASIS_DT\s*(<=|<)\s*{current_date_expr}",
    normalized,
)
if lower_relative and upper_relative_sub:
    ensure_max_7_days(
        relative_span(
            int(lower_relative.group(2)),
            lower_relative.group(1),
            int(upper_relative_sub.group(2)),
            upper_relative_sub.group(1),
        )
    )
if lower_relative and upper_relative_now:
    ensure_max_7_days(
        relative_span(
            int(lower_relative.group(2)),
            lower_relative.group(1),
            0,
            upper_relative_now.group(1),
        )
    )

fail(
    "검증 가능한 basis_dt 범위 조건이 없습니다. "
    "예: basis_dt BETWEEN '2026-03-01' AND '2026-03-07' "
    "또는 basis_dt >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 DAY) AND basis_dt < CURRENT_DATE()"
)
PY
  ); then
    echo "$validation_output" >&2
    return 1
  fi

  return 0
}

if contains_dw_biz_log_reference; then
  if ! validate_dw_biz_log_window; then
    exit 2
  fi
fi

# DML / DDL block-list
PATTERNS=(
  '\bINSERT[[:space:]]+INTO\b'
  '\bUPDATE[[:space:]]+[A-Z0-9_.]+'
  '\bDELETE[[:space:]]+FROM\b'
  '\bCREATE[[:space:]]+(OR[[:space:]]+REPLACE[[:space:]]+)?(TABLE|VIEW|SCHEMA|DATABASE|FUNCTION|PROCEDURE|MATERIALIZED[[:space:]]+VIEW)\b'
  '\bDROP[[:space:]]+(TABLE|VIEW|SCHEMA|DATABASE|FUNCTION|PROCEDURE|MATERIALIZED[[:space:]]+VIEW)\b'
  '\bALTER[[:space:]]+(TABLE|VIEW|SCHEMA|DATABASE)\b'
  '\bTRUNCATE[[:space:]]+TABLE\b'
  '\bMERGE[[:space:]]+INTO\b'
  '\bEXPORT[[:space:]]+DATA\b'
  '\bCALL[[:space:]]+'
)

for pattern in "${PATTERNS[@]}"; do
  if printf '%s' "$UPPER_COMMAND" | grep -qE "$pattern"; then
    echo "BLOCKED: 데이터 변경(DML/DDL) 쿼리는 허용되지 않습니다. SELECT 문만 사용하세요." >&2
    exit 2
  fi
done

# Dry-run size guard
MAX_BYTES_GB=100
MAX_BYTES=$(( MAX_BYTES_GB * 1024 * 1024 * 1024 ))

if echo "$COMMAND" | grep -qE -- '--dry.?run'; then
  exit 0
fi

DRY_CMD=$(printf '%s' "$COMMAND" | sed 's/\(bq[[:space:]]*query\)/\1 --dry_run/')

if command -v gtimeout >/dev/null 2>&1; then
  DRY_RESULT=$(gtimeout 30 bash -c "$DRY_CMD" 2>&1) || true
else
  DRY_RESULT=$(bash -c "$DRY_CMD" 2>&1) || true
fi

BYTES=$(
  printf '%s' "$DRY_RESULT" \
    | grep -oE '[0-9]+ bytes of data' \
    | grep -oE '^[0-9]+' \
    | head -1 \
    || true
)

if [ -z "${BYTES:-}" ]; then
  exit 0
fi

if [ "$BYTES" -gt "$MAX_BYTES" ]; then
  GB=$(awk "BEGIN {printf \"%.1f\", $BYTES / 1073741824}")
  echo "BLOCKED: 이 쿼리는 약 ${GB}GB를 처리할 예정이에요 (허용 한도: ${MAX_BYTES_GB}GB)." >&2
  echo "날짜 범위나 파티션 조건을 더 좁혀서 다시 시도해주세요." >&2
  exit 2
fi

exit 0
