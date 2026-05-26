#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-}"
[[ -z "$PROJECT" ]] && { echo "Usage: $0 <PROJECT>"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NF_BIN="$HOME/tools/nextflow"

OUT_DIR="$HOME/output/$PROJECT"
INPUT_DIR="$OUT_DIR/input"
LOG_DIR="$HOME/output/log/$PROJECT"
STATE_FILE="$LOG_DIR/watchdog_state.env"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
ERROR_LOG="$LOG_DIR/error.log"

mkdir -p "$LOG_DIR"

stages=("OUTBREAK_ANALYZER")
scripts=("run_OUTBREAK_ANALYZER.sh")
result_dirs=("outbreakANALYSIS")
# Combined single-stage pipeline; check every 30 min
check_intervals=(1800)
max_restarts=2
POLL_INTERVAL=15
NUM_STAGES=1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$WATCHDOG_LOG"
}

log_error() {
  local context="$1"
  local action="$2"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  {
    echo "[$ts] ============================="
    echo "[$ts] ERROR: $PROJECT / $context"
    echo "[$ts] Action taken: $action"
    echo "[$ts] ============================="
  } | tee -a "$ERROR_LOG" >> "$WATCHDOG_LOG"
}

load_state() {
  current_stage_idx=0
  stage_pid=""
  stage_started_at=0
  last_checkin_at=0
  last_progress_count=-1
  stalled_intervals=0
  restart_count=0
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

save_state() {
  cat > "$STATE_FILE" <<EOF
current_stage_idx=$current_stage_idx
stage_pid=${stage_pid:-}
stage_started_at=$stage_started_at
last_checkin_at=$last_checkin_at
last_progress_count=$last_progress_count
stalled_intervals=$stalled_intervals
restart_count=$restart_count
EOF
}

stage_log_path()  { echo "$LOG_DIR/stage_${1}_${stages[$1]}.log"; }
stage_exit_path() { echo "$LOG_DIR/stage_${1}_${stages[$1]}.exit"; }

stage_log_has_disk_error() {
  grep -q "No space left on device" "$(stage_log_path "$1")" 2>/dev/null
}

clean_work_dir() {
  local idx="$1"
  log "Disk space error detected for ${stages[$idx]} — running nextflow clean"
  (cd "$SCRIPT_DIR" && "$NF_BIN" clean -f -but last >> "$WATCHDOG_LOG" 2>&1) || true
  log "nextflow clean done; free space: $(df -h / | awk 'NR==2{print $4}')"
}

stage_progress_count() {
  local rdir="$OUT_DIR/results/${result_dirs[$1]}"
  if [[ -d "$rdir" ]]; then
    find "$rdir" -type f | wc -l | tr -d ' '
  else
    echo 0
  fi
}

start_stage() {
  local idx="$1"
  local script_path="$INPUT_DIR/${scripts[$idx]}"
  local slog sexit

  if [[ ! -f "$script_path" ]]; then
    log_error "start_stage ${stages[$idx]}" "Cannot start — script not found: $script_path"
    log "FATAL: Script not found: $script_path"
    exit 1
  fi

  slog="$(stage_log_path "$idx")"
  sexit="$(stage_exit_path "$idx")"
  rm -f "$sexit"

  log "Starting stage $((idx+1))/$NUM_STAGES: ${stages[$idx]} (check-in every ${check_intervals[$idx]}s)"
  nohup bash -lc "bash '$script_path' > '$slog' 2>&1; echo \$? > '$sexit'" >/dev/null 2>&1 &
  stage_pid=$!
  stage_started_at=$(date +%s)
  last_progress_count=-1
  stalled_intervals=0
  restart_count=0
  save_state
}

capture_stage_tail() {
  local idx="$1"
  local slog
  slog="$(stage_log_path "$idx")"
  if [[ -f "$slog" ]]; then
    echo "--- Last 30 lines of ${stages[$idx]} log ($(date '+%Y-%m-%d %H:%M:%S')) ---"
    tail -n 30 "$slog" 2>/dev/null || true
    echo "---"
  fi
}

investigate_stall() {
  local idx="$1"
  log "Investigating no-movement for ${stages[$idx]}"
  {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STALL: ${stages[$idx]} (stage $((idx+1))/$NUM_STAGES)"
    capture_stage_tail "$idx"
  } | tee -a "$ERROR_LOG" >> "$WATCHDOG_LOG"
}

restart_stage() {
  local idx="$1"
  local sexit
  sexit="$(stage_exit_path "$idx")"

  if [[ -n "${stage_pid:-}" ]] && ps -p "$stage_pid" >/dev/null 2>&1; then
    kill "$stage_pid" 2>/dev/null || true
    sleep 2
    kill -9 "$stage_pid" 2>/dev/null || true
  fi

  pkill -9 -f "nextflow.*$PROJECT" >/dev/null 2>&1 || true
  rm -f "$sexit"
  restart_count=$((restart_count + 1))
  log_error "Stage ${stages[$idx]} stalled or failed" "Restart #$restart_count"
  log "Restarting ${stages[$idx]} (restart #$restart_count of $max_restarts)"
  start_stage "$idx"
}

# ── Main ────────────────────────────────────────────────────────────────────

load_state

log "Watchdog started for $PROJECT (stage_idx=$current_stage_idx, pid=$$)"

if (( current_stage_idx >= NUM_STAGES )); then
  log "All stages already completed for $PROJECT"
  exit 0
fi

if [[ -z "${stage_pid:-}" ]] || ! ps -p "$stage_pid" >/dev/null 2>&1; then
  start_stage "$current_stage_idx"
fi

while true; do
  now=$(date +%s)

  if (( current_stage_idx >= NUM_STAGES )); then
    log "Workflow complete for $PROJECT"
    exit 0
  fi

  idx="$current_stage_idx"
  sexit="$(stage_exit_path "$idx")"
  interval="${check_intervals[$idx]}"

  running=0
  if [[ -n "${stage_pid:-}" ]] && ps -p "$stage_pid" >/dev/null 2>&1; then
    running=1
  fi

  # ── Stage finished (process gone + exit file written) ───────────────────
  if (( running == 0 )) && [[ -f "$sexit" ]]; then
    exit_code=$(cat "$sexit" 2>/dev/null || echo 1)

    if [[ "$exit_code" == "0" ]]; then
      log "Stage ${stages[$idx]} completed successfully"
      current_stage_idx=$((current_stage_idx + 1))
      stage_pid=""
      stage_started_at=0
      last_progress_count=-1
      stalled_intervals=0
      restart_count=0
      save_state
      if (( current_stage_idx < NUM_STAGES )); then
        start_stage "$current_stage_idx"
      else
        log "OUTBREAK_ANALYZER COMPLETE for $PROJECT"
        log "Deliverables in: $OUT_DIR/results/outbreakANALYSIS/report_outbreak/"
        exit 0
      fi
      sleep 2
      continue
    fi

    # Non-zero exit
    log "Stage ${stages[$idx]} exited with code $exit_code"
    {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAILED EXIT: ${stages[$idx]} exit_code=$exit_code"
      capture_stage_tail "$idx"
    } >> "$ERROR_LOG"
    investigate_stall "$idx"

    if stage_log_has_disk_error "$idx"; then
      clean_work_dir "$idx"
    fi

    if (( restart_count < max_restarts )); then
      restart_stage "$idx"
    else
      log_error "Stage ${stages[$idx]} failed after $max_restarts restarts (exit=$exit_code)" "Manual intervention required — stopping watchdog"
      log "FATAL: ${stages[$idx]} failed repeatedly. Manual intervention required."
      exit 1
    fi
  fi

  # ── Periodic progress check at stage-specific interval ──────────────────
  if (( now - last_checkin_at >= interval )); then
    progress_count=$(stage_progress_count "$idx")
    log "CHECK-IN [${stages[$idx]}] pid=${stage_pid:-none} files=$progress_count interval=${interval}s"

    if (( last_progress_count >= 0 )) && (( progress_count <= last_progress_count )); then
      stalled_intervals=$((stalled_intervals + 1))
      investigate_stall "$idx"

      if (( stalled_intervals >= 2 )); then
        if (( restart_count < max_restarts )); then
          log "No file movement across 2 consecutive check-ins; restarting ${stages[$idx]}"
          restart_stage "$idx"
        else
          log_error "No movement persists and restart limit reached for ${stages[$idx]}" "Manual intervention required — stopping watchdog"
          log "FATAL: No movement persists and restart limit reached for ${stages[$idx]}"
          exit 1
        fi
      else
        log "WARN: No file movement for ${stages[$idx]} (stalled_intervals=$stalled_intervals/2)"
      fi
    else
      stalled_intervals=0
    fi

    last_progress_count=$progress_count
    last_checkin_at=$now
    save_state
  fi

  sleep "$POLL_INTERVAL"
done
