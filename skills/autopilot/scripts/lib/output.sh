#!/bin/bash
# Human-readable output, durable logs, and timing helpers.

set -e

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

now_epoch() {
  date '+%s'
}

sanitize_message() {
  local value="$1"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value:0:500}"
  printf '%s' "$value"
}

format_duration() {
  local seconds="$1"
  if [[ "$seconds" -lt 60 ]]; then
    printf '%ss' "$seconds"
  elif [[ "$seconds" -lt 3600 ]]; then
    printf '%sm' "$((seconds / 60))"
  else
    printf '%sh%02dm' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
  fi
}

file_mtime() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf '0'
  elif stat -f '%m' "$path" >/dev/null 2>&1; then
    stat -f '%m' "$path"
  else
    stat -c '%Y' "$path"
  fi
}

iso_from_epoch() {
  local epoch="$1"
  if [[ "$epoch" -le 0 ]]; then
    printf ''
  elif date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ'
  else
    date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

shell_join() {
  local result="" quoted argument
  for argument in "$@"; do
    printf -v quoted '%q' "$argument"
    result="${result}${quoted} "
  done
  printf '%s' "${result% }"
}

emit_stderr() {
  printf 'Autopilot: %s\n' "$1" >&2
}

write_log() {
  local message timestamp_value
  message="$(sanitize_message "$1")"
  timestamp_value="$(timestamp)"
  if [[ -n "$LOG_FILE" ]] && ! printf '%s Autopilot: %s\n' "$timestamp_value" "$message" >>"$LOG_FILE"; then
    emit_stderr "warning: could not write canonical log $LOG_FILE"
  fi
  if [[ -n "$LOG_MIRROR_FILE" && "$LOG_MIRROR_FILE" != "$LOG_FILE" ]]; then
    if ! { printf '%s Autopilot: %s\n' "$timestamp_value" "$message" >>"$LOG_MIRROR_FILE"; } 2>/dev/null; then
      if [[ -n "$RUN_DIR" ]] && mkdir "$RUN_DIR/.log-mirror-warning" 2>/dev/null; then
        emit_stderr "warning: log mirror unavailable; canonical log continues at $LOG_FILE"
      fi
    fi
  fi
}

announce() {
  local message
  message="$(sanitize_message "$1")"
  write_log "$message"
  emit_stderr "$message"
}

mark_activity() {
  [[ -z "$ACTIVITY_FILE" ]] || touch "$ACTIVITY_FILE"
}

record_activity() {
  mark_activity
  write_log "$1"
}

announce_activity() {
  mark_activity
  announce "$1"
}
