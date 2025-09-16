#!/usr/local/bin/bash

# === Helper function to build disk arguments ===
# Returns the disk arguments string.
# Optionally, it can store the next available disk slot number in a variable
# provided by the caller.
build_disk_args() {
  local VM_DIR="$1"
  local VAR_NEXT_SLOT="$2"
  local DISK_ARGS=""
  local DISK_DEV_NUM=3 # Starting PCI slot for disks

  local CURRENT_DISK_IDX=0
  while true; do
    local CURRENT_DISK_VAR="DISK_${CURRENT_DISK_IDX}"
    local CURRENT_DISK_FILENAME="${!CURRENT_DISK_VAR}"

    if [ -z "$CURRENT_DISK_FILENAME" ]; then
      break # No more disks configured
    fi

    local CURRENT_DISK_TYPE_VAR="DISK_${CURRENT_DISK_IDX}_TYPE"
    local DISK_TYPE="${!CURRENT_DISK_TYPE_VAR:-virtio-blk}"

    local CURRENT_DISK_PATH="$CURRENT_DISK_FILENAME"
    if [[ ! "$CURRENT_DISK_PATH" =~ ^/ ]]; then
        CURRENT_DISK_PATH="$VM_DIR/$CURRENT_DISK_FILENAME"
    fi

    if [ ! -f "$CURRENT_DISK_PATH" ]; then
      display_and_log "ERROR" "Disk image '$CURRENT_DISK_PATH' not found!"
      return 1
    fi

    # Add escaped quotes around the disk path
    DISK_ARGS+=" -s ${DISK_DEV_NUM}:0,${DISK_TYPE},\"${CURRENT_DISK_PATH}\""
    DISK_DEV_NUM=$((DISK_DEV_NUM + 1))
    CURRENT_DISK_IDX=$((CURRENT_DISK_IDX + 1))
  done

  # If a variable name was passed as the second argument, assign the next slot number to it.
  if [ -n "$VAR_NEXT_SLOT" ]; then
    # Use eval to assign to the variable name provided by the caller.
    # This is a more portable alternative to namerefs.
    eval "$VAR_NEXT_SLOT=$DISK_DEV_NUM"
  fi

  echo "$DISK_ARGS"
  return 0
}