#!/bin/sh

VMNAME="$1"
BASEPATH="/home/admin/vm-bhvye"
VM_DIR="$BASEPATH/vm/$VMNAME"
CONF_FILE="$VM_DIR/vm.conf"
PID_FILE="$VM_DIR/vm.pid"

# === fucntion logging
log() {
  echo "[$(date '+%F %T')] [INFO] $1"
}

# === Validasi input
if [ -z "$VMNAME" ]; then
  echo "Usage: $0 <vmname>"
  exit 1
fi

# === Validasi konfigurasi
if [ ! -f "$CONF_FILE" ]; then
  echo "[ERROR] Konfigurasi $CONF_FILE tidak ditemukan"
  exit 1
fi

. "$CONF_FILE"

log "Stopped VM '$VMNAME'..."

# === Cek PID dari file atau dari proses aktif
if [ -f "$PID_FILE" ]; then
  VM_PID=$(cat "$PID_FILE")
else
  VM_PID=$(pgrep -f "bhyve.*$VMNAME")
fi

if [ -z "$VM_PID" ]; then
  log "VM '$VMNAME' Not Running."
  exit 0
fi

# === Kirim sinyal TERM ke bhyve
log "Send signal TERM ke PID $VM_PID"
kill "$VM_PID"

# === Tunggu proses bhyve berhenti
sleep 1
if ps -p "$VM_PID" > /dev/null 2>&1; then
  log "PID $VM_PID masih running, Proses KILL..."
  kill -9 "$VM_PID"
  sleep 1
fi

# === Hapus file PID
rm -f "$PID_FILE"

log "VM '$VMNAME' berhasil Stop."
