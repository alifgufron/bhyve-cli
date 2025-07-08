#!/bin/sh

# === Validasi input ===
if [ -z "$1" ]; then
  echo "Usage: $0 <vmname>"
  exit 1
fi

VMNAME="$1"
BASEPATH="/home/admin/vm-bhvye"
VM_DIR="$BASEPATH/vm/$VMNAME"
CONF_FILE="$VM_DIR/vm.conf"
LOG_FILE="$VM_DIR/vm.log"

# === Fungsi log ===
log() {
  echo "[$(date '+%F %T')] [INFO] $1" | tee -a "$LOG_FILE"
}

# === Cek file konfigurasi ===
if [ ! -f "$CONF_FILE" ]; then
  echo "[ERROR] VM '$VMNAME' tidak ditemukan."
  exit 1
fi

# === Load konfigurasi ===
. "$CONF_FILE"

log "Menghapus VM '$VMNAME'..."

# === Hentikan bhyve jika masih jalan ===
if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
  log "VM masih berjalan. Menghentikan proses bhyve..."
  pkill -f "bhyve.*$VMNAME"
  sleep 1
fi

# === Destroy dari kernel memory ===
if bhyvectl --vm="$VMNAME" --destroy > /dev/null 2>&1; then
  log "VM dihancurkan dari kernel memory."
fi

# === Hapus TAP dari bridge ===
if ifconfig "$BRIDGE" | grep -qw "$TAP"; then
  log "Menghapus TAP '$TAP' dari bridge '$BRIDGE'..."
  ifconfig "$BRIDGE" deletem "$TAP"
fi

# === Hapus TAP interface ===
if ifconfig "$TAP" > /dev/null 2>&1; then
  log "Menghapus TAP interface '$TAP'..."
  ifconfig "$TAP" destroy
fi

# === Hapus direktori VM ===
log "Menghapus direktori VM: $VM_DIR"
rm -rf "$VM_DIR"

echo -e "VM '$VMNAME' berhasil dihapus."
