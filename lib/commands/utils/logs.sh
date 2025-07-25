#!/usr/local/bin/bash

# === Subcommand: logs ===
cmd_logs() {
  if [ -z "$1" ] || [ "$1" = "--help" ] || [ "$2" = "--help" ]; then
    cmd_logs_usage
    exit 0
  fi

  local VMNAME="$1"
  local TAIL_LINES=100 # Default to 100 lines
  local FOLLOW_LOG=false
  local NEXT_IS_TAIL_VALUE=false

  log "DEBUG" "Initial VMNAME: $VMNAME"
  log "DEBUG" "Initial TAIL_LINES: $TAIL_LINES"

  # Shift VMNAME so that $@ contains only options and their values
  shift
  log "DEBUG" "Arguments after shifting VMNAME: $@"

  for arg in "$@"; do
    log "DEBUG" "Processing argument: $arg"
    if [ "$NEXT_IS_TAIL_VALUE" = true ]; then
      log "DEBUG" "NEXT_IS_TAIL_VALUE is true. Current arg: $arg"
      if [[ "$arg" =~ ^[0-9]+$ ]]; then
        TAIL_LINES="$arg"
        NEXT_IS_TAIL_VALUE=false
        log "DEBUG" "TAIL_LINES set to: $TAIL_LINES"
      else
        display_and_log "ERROR" "Invalid number for --tail option: $arg."
        cmd_logs_usage
        exit 1
      fi
    elif [ "$arg" = "--tail" ]; then
      NEXT_IS_TAIL_VALUE=true
      log "DEBUG" "--tail option found. NEXT_IS_TAIL_VALUE set to true."
    elif [ "$arg" = "-f" ]; then
      FOLLOW_LOG=true
      log "DEBUG" "-f option found. FOLLOW_LOG set to true."
    else
      log "DEBUG" "Unexpected argument: $arg"
      : # Do nothing for now, as only --tail and -f are expected
    fi
  done

  log "DEBUG" "Final TAIL_LINES before tail command: $TAIL_LINES"
  log "DEBUG" "Final FOLLOW_LOG before tail command: $FOLLOW_LOG"

  load_vm_config "$VMNAME"

  if [ ! -f "$LOG_FILE" ]; then
    display_and_log "ERROR" "Log file for VM '$VMNAME' not found."
    exit 1
  fi

  if [ "$FOLLOW_LOG" = true ]; then
    tail -f "$LOG_FILE"
  else
    tail -n "$TAIL_LINES" "$LOG_FILE"
  fi
}
