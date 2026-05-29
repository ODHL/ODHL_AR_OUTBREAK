#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-}"
[[ -z "$PROJECT" ]] && { echo "Usage: $0 <PROJECT>"; exit 1; }

LOG_DIR="$HOME/output/log/$PROJECT"
PID_FILE="$LOG_DIR/watchdog.pid"

if [[ -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  if [[ -n "${pid:-}" ]] && ps -p "$pid" >/dev/null 2>&1; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

pkill -9 -f "pipeline_watchdog_worker.sh $PROJECT" >/dev/null 2>&1 || true

echo "Stopped watchdog for $PROJECT"
