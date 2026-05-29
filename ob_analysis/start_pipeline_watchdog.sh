#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-}"
[[ -z "$PROJECT" ]] && { echo "Usage: $0 <PROJECT>"; exit 1; }

WORKER="$(cd "$(dirname "$0")" && pwd)/pipeline_watchdog_worker.sh"
LOG_DIR="$HOME/output/log/$PROJECT"
PID_FILE="$LOG_DIR/watchdog.pid"
START_LOG="$LOG_DIR/start_watchdog.log"

mkdir -p "$LOG_DIR"

if [[ -f "$PID_FILE" ]]; then
  old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
  if [[ -n "${old_pid:-}" ]] && ps -p "$old_pid" >/dev/null 2>&1; then
    echo "Watchdog already running for $PROJECT (PID $old_pid)"
    echo "  Logs: $LOG_DIR/"
    exit 0
  fi
fi

chmod +x "$WORKER"

setsid -f bash -lc "nohup '$WORKER' '$PROJECT' >/dev/null 2>&1 < /dev/null & echo \$! > '$PID_FILE'"
sleep 2

new_pid=$(cat "$PID_FILE" 2>/dev/null || true)
if [[ -z "${new_pid:-}" ]] || ! ps -p "$new_pid" >/dev/null 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start watchdog for $PROJECT" | tee -a "$START_LOG"
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Started watchdog for $PROJECT (PID $new_pid)" | tee -a "$START_LOG"
echo "  Logs:  $LOG_DIR/watchdog.log"
echo "  Errors: $LOG_DIR/error.log"
