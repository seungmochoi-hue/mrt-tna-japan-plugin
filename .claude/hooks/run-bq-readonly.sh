#!/bin/bash
# Claude Code에서 bq query를 실행할 때 guard를 통과시키는 wrapper.

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: ./.claude/hooks/run-bq-readonly.sh bq <query|show|ls|head|version> <args...>" >&2
  exit 1
fi

if [ "$1" != "bq" ]; then
  echo "BLOCKED: run-bq-readonly.sh는 bq 명령 전용입니다." >&2
  exit 2
fi

case "$2" in
  query|show|ls|head|version) ;;
  *)
    echo "BLOCKED: bq는 query / show / ls / head / version 명령만 허용됩니다." >&2
    exit 2
    ;;
esac

COMMAND_STR="$*"
INPUT_JSON=$(jq -n --arg cmd "$COMMAND_STR" '$ARGS.positional as $argv | {tool_name:"Bash", tool_input:{command:$cmd, argv:$argv}}' --args -- "$@")

set +e
printf '%s' "$INPUT_JSON" | "$(dirname "$0")/bq-query-guard.sh"
GUARD_EXIT=$?
set -e

if [ "$GUARD_EXIT" -ne 0 ]; then
  exit "$GUARD_EXIT"
fi

exec "$@"
