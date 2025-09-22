#!/usr/local/bin/bash

# === Subcommand: logs ===
cmd_logs() {
  load_config # Ensure GLOBAL_LOG is set
  local VMNAME=""
  local TAIL_LINES=100
  local FOLLOW_LOG=false

  # Parse options first
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f)
        FOLLOW_LOG=true
        shift
        ;;
      --tail)
        if [[ "$2" =~ ^[0-9]+$ ]]; then
          TAIL_LINES="$2"
          shift 2
        else
          # It might be `logs --tail` without a number, which is an error, or `logs --tail vmname` which is also wrong.
          # Or it could be `logs vmname --tail num` where vmname is now $1
          if [ -z "$2" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
             display_and_log "ERROR" "--tail requires a numeric argument."
             cmd_logs_usage
             exit 1
          fi
        fi
        ;;
      --help)
        cmd_logs_usage
        exit 0
        ;;
      -*)
        display_and_log "ERROR" "Unknown option: $1"
        cmd_logs_usage
        exit 1
        ;;
      *)
        # The first non-option argument is the VM name
        if [ -z "$VMNAME" ]; then
          VMNAME="$1"
          shift
        else
          # Ignore other non-option arguments
          shift
        fi
        ;;
    esac
  done

  local LOG_FILE
  if [ -z "$VMNAME" ]; then
    # No VM name provided, use global log
    LOG_FILE="${GLOBAL_LOG_FILE}"
  else
    # A VM name is provided, find its log file
    local found_vm_info
    found_vm_info=$(find_any_vm "$VMNAME")

    if [ -z "$found_vm_info" ]; then
      display_and_log "ERROR" "VM '$VMNAME' not found in any datastore."
      exit 1
    fi

    local vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
    local datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
    local vm_dir="$datastore_path/$VMNAME"

    if [ "$vm_source" == "vm-bhyve" ]; then
      LOG_FILE="$vm_dir/vm-bhyve.log"
    else
      LOG_FILE="$vm_dir/vm.log"
    fi
  fi

  if [ ! -f "$LOG_FILE" ]; then
    display_and_log "ERROR" "Log file not found at '$LOG_FILE'."
    exit 1
  fi

  if [ "$FOLLOW_LOG" = true ]; then
    tail -f "$LOG_FILE"
  else
    tail -n "$TAIL_LINES" "$LOG_FILE"
  fi
}
