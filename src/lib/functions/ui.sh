#!/usr/local/bin/bash

# === Log Function with Timestamp ===
log() {
  local TIMESTAMP_MESSAGE
  TIMESTAMP_MESSAGE="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
  # Write to VM-specific log file if LOG_FILE is set
  if [ -n "$LOG_FILE" ]; then
    echo "$TIMESTAMP_MESSAGE" >> "$LOG_FILE"
  fi
  # Always write to global log file for verbose debugging
  if [ -n "$GLOBAL_LOG_FILE" ]; then
    echo "$TIMESTAMP_MESSAGE" >> "$GLOBAL_LOG_FILE"
  fi
}

# === Function to echo messages to console without timestamp ===
echo_message() {
  echo -e "$1" >&2
}

# === Function to display message to console with timestamp and log to file ===
display_and_log() {
  local LEVEL="$1"
  local MESSAGE="$2"
  local TIMESTAMP_MESSAGE
  TIMESTAMP_MESSAGE="[$(date '+%Y-%m-%d %H:%M:%S')] [$LEVEL] $MESSAGE"
  echo "$MESSAGE" >&2 # === Display to console without timestamp or INFO prefix ===
  # Write to VM-specific log file if LOG_FILE is set
  if [ -n "$LOG_FILE" ]; then
    echo "$TIMESTAMP_MESSAGE" >> "$LOG_FILE"
  fi
  # Always write to global log file
  if [ -n "$GLOBAL_LOG_FILE" ]; then
    echo "$TIMESTAMP_MESSAGE" >> "$GLOBAL_LOG_FILE"
  fi
}

# === Function to write to global log file only ===
log_to_global_file() {
  local LEVEL="$1"
  local MESSAGE="$2"
  if [ -n "$GLOBAL_LOG_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LEVEL] $MESSAGE" >> "$GLOBAL_LOG_FILE"
  fi
}

# === Spinner Functions ===
_spinner_chars='|/-\'
_spinner_pid=

start_spinner() {
  local message="$1"
  echo -n "$message"
  (
    while :; do
      for (( i=0; i<${#_spinner_chars}; i++ )); do
        echo -ne "${_spinner_chars:$i:1}"
        echo -ne "\b"
        sleep 0.1
      done
    done
  ) &
  _spinner_pid=$!
  trap stop_spinner EXIT
}

stop_spinner() {
  local message="$1"
  if [[ -n "$_spinner_pid" ]]; then
    kill "$_spinner_pid" >/dev/null 2>&1
    wait "$_spinner_pid" 2>/dev/null
    echo -ne "\r\033[K"
  fi
  if [[ -n "$message" ]]; then
    echo_message "$message"
  fi
}