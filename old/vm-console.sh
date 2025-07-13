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

# === Cek file konfigurasi ===
if [ ! -f "$CONF_FILE" ]; then
  echo "[ERROR] Konfigurasi VM '$VMNAME' tidak ditemukan: $CONF_FILE"
  exit 1
fi

# === Load konfigurasi ===
. "$CONF_FILE"

# === Cek device console ===
DEVICE_B="/dev/${CONSOLE}B"

if [ ! -e "$DEVICE_B" ]; then
  echo "[ERROR] Device console '$DEVICE_B' tidak ditemukan."
  echo "Pastikan VM sudah pernah dijalankan minimal 1x, atau device sudah dibuat."
  exit 1
fi

echo ">>> Mengakses console VM '$VMNAME'"
echo ">>> Keluar dengan ~."

# === Masuk ke console ===
cu -l "$DEVICE_B"
