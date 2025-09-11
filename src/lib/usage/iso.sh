#!/usr/local/bin/bash

# === Usage function for ISO ===
cmd_iso_usage() {
  echo_message "Usage: $(basename "$0") iso [list | <URL> | delete <iso_filename>]"
  echo_message "\nSubcommands:"
  echo_message "  list         - List all ISO images in $ISO_DIR."
  echo_message "  <URL>        - Download an ISO image from the specified URL to $ISO_DIR."
  echo_message "  delete <iso_filename> - Delete a specified ISO image from $ISO_DIR."
  echo_message "\nExample:"
  echo_message "  $(basename "$0") iso list"
  echo_message "  $(basename "$0") iso https://example.com/freebsd.iso"
  echo_message "  $(basename "$0") iso delete my_iso.iso"
}

