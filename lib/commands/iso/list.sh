#!/usr/local/bin/bash

# === Subcommand: iso list ===
cmd_iso_list() {
  log "Listing ISO files in $ISO_DIR..."
  if [ ! -d "$ISO_DIR" ]; then
    display_and_log "INFO" "ISO directory '$ISO_DIR' not found. Creating it."
    mkdir -p "$ISO_DIR"
  fi
  mapfile -t ISO_LIST < <(find "$ISO_DIR" -type f -name "*.iso" 2>/dev/null)
  if [ ${#ISO_LIST[@]} -eq 0 ]; then
    display_and_log "INFO" "No ISO files found in $ISO_DIR."
  else
    echo_message "\nAvailable ISOs in $ISO_DIR:"
    local count=1
    for iso in "${ISO_LIST[@]}"; do
      local iso_filename=$(basename "$iso")
      local iso_size_bytes=$(stat -f %z "$iso")
      local iso_size_gb=$(echo "scale=2; $iso_size_bytes / (1024 * 1024 * 1024)" | bc)
      echo_message "$((count++)). $iso_filename (${iso_size_gb}GB)"
    done
  fi
}

