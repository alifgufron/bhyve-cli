#!/usr/local/bin/bash

# === Subcommand: logs ===
cmd_logs() {
  if [ -z "$1" ] || [ "$1" = "--help" ]; then
    cmd_logs_usage
    exit 0
  fi

  local VMNAME="$1"
  local TAIL_LINES=100
  local FOLLOW_LOG=false

  # Shift to process options like -f and --tail
  shift

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
          display_and_log "ERROR" "Invalid number for --tail option: '$2'."
          exit 1
        fi
        ;;
      *)
        # Ignore unknown arguments for now
        shift
        ;;
    esac
  done

  # Use the centralized find_any_vm function
  local found_vm_info
  found_vm_info=$(find_any_vm "$VMNAME")

  if [ -z "$found_vm_info" ]; then
    display_and_log "ERROR" "VM '$VMNAME' not found in any datastore."
    exit 1
  fi

  local vm_source=$(echo "$found_vm_info" | cut -d':' -f1)
  local datastore_path=$(echo "$found_vm_info" | cut -d':' -f3)
  local vm_dir="$datastore_path/$VMNAME"

  local LOG_FILE
  if [ "$vm_source" == "vm-bhyve" ]; then
    LOG_FILE="$vm_dir/vm-bhyve.log"
  else
    LOG_FILE="$vm_dir/vm.log"
  fi

  if [ ! -f "$LOG_FILE" ]; then
    display_and_log "ERROR" "Log file for VM '$VMNAME' not found at '$LOG_FILE'."
    exit 1
  fi

  if [ "$FOLLOW_LOG" = true ]; then
    tail -f "$LOG_FILE"
  else
    tail -n "$TAIL_LINES" "$LOG_FILE"
  fi
}
