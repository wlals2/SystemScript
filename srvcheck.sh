#!/usr/bin/env bash
# ELK 서비스 확인하는 스크립트
set -euo pipefail

PATTERN=${1:-'elasticsearch|kibana|logstash|java|spring|node'}

echo "== Process match: $PATTERN =="
PIDS=$(pgrep -f "$PATTERN" || true)
if [ -z "${PIDS}" ]; then
  echo "No matching process."
  exit 1
fi

for PID in $PIDS; do
  echo "----------------------------------------"
  echo "PID: $PID"
  echo "CMD: $(tr '\0' ' ' </proc/$PID/cmdline)"
  echo "Exe: $(readlink -f /proc/$PID/exe 2>/dev/null || echo 'n/a')"
  echo "CWD: $(readlink -f /proc/$PID/cwd 2>/dev/null || echo 'n/a')"

  echo "-- Open config/log files (best-effort) --"
  lsof -p "$PID" 2>/dev/null | egrep '\.(yml|yaml|json|properties|conf|log)$' | awk '{print $9}' | sort -u | sed 's/^/  /' || true

  echo "-- Listening ports --"
  ss -tulpn 2>/dev/null | grep -w "$PID/" || echo "  (no listening ports by this PID)"
done