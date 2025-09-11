#!/usr/local/bin/bash

# === Prerequisite Checks ===
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo_message "ERROR This script must be run with superuser (root) privileges."
    exit 1
  fi
}

check_kld() {
  if ! kldstat -q -m "$1"; then
    display_and_log "ERROR" "Kernel module '$1.ko' is not loaded. Please run 'kldload $1'."
    exit 1
  fi
}

# === Helper function to get tar compression flags ===
get_tar_compression_flags() {
  local format="$1"
  case "$format" in
    gz) echo "-z" ;;
    bz2) echo "-j" ;;
    xz) echo "-J" ;;
    lz4) echo "--use-compress-program=lz4" ;;
    zst) echo "--use-compress-program=zstd" ;;
    *) echo "-z" ;; # Default to gzip
  esac
}

# === Helper function to get compression extension suffix ===
get_compression_extension_suffix() {
  local format="$1"
  case "$format" in
    gz) echo "gz" ;;
    bz2) echo "bz2" ;;
    xz) echo "xz" ;;
    lz4) echo "lz4" ;;
    zst) echo "zst" ;;
    *) echo "gz" ;; # Default to gz
  esac
}
