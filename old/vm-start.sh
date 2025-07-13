#!/bin/sh

VMNAME="$1"
BASEPATH="/home/admin/vm-bhvye"
VM_DIR="$BASEPATH/vm/$VMNAME"
CONF_FILE="$VM_DIR/vm.conf"

# === Fungsi logging
log() {
  echo "[$(date '+%F %T')] [INFO] $1" | tee -a "$LOG_FILE"
}

# === Validasi input dan konfigurasi
if [ -z "$VMNAME" ] || [ ! -f "$CONF_FILE" ]; then
  echo "Usage: $0 <vmname>"
  echo "[ERROR] VM config not found: $CONF_FILE"
  exit 1
fi

# === Load konfigurasi
. "$CONF_FILE"
LOG_FILE="$VM_DIR/vm.log"

log "Prepare Config $VMNAME"

# ==== Cek apakah bhyve masih berjalan
if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
  log "VM '$VMNAME' masih berjalan nich. Stopped..."
  pkill -f "bhyve.*$VMNAME"
  sleep 1
fi

# === Destroy VM jika masih tersisa di kernel
if bhyvectl --vm="$VMNAME" --destroy > /dev/null 2>&1; then
  log "VM '$VMNAME' sebelumnya masih ada di memori. Stopped."
fi

# === Buat TAP interface jika belum ada
if ! ifconfig "$TAP" > /dev/null 2>&1; then
  log "TAP '$TAP' belum ada. Membuat..."
  ifconfig "$TAP" create description "vm-$VMNAME"
  ifconfig "$TAP" up
  log "TAP '$TAP' dibuat dan diaktifkan."
else
  ifconfig "$TAP" up
  log "TAP '$TAP' sudah ada dan diaktifkan."
fi

# === Tambahkan ke bridge jika belum menjadi member
if ! ifconfig "$BRIDGE" | grep -qw "$TAP"; then
  ifconfig "$BRIDGE" addm "$TAP"
  log "TAP '$TAP' ditambahkan ke bridge '$BRIDGE'"
else
  log "TAP '$TAP' sudah terhubung ke bridge '$BRIDGE'"
fi

# === Pastikan device nmdm tersedia
if ! [ -e "/dev/${CONSOLE}A" ] && ! [ -e "/dev/${CONSOLE}B" ]; then
  log "Membuat device /dev/${CONSOLE}A dan /dev/${CONSOLE}B"
  mdm_number="${CONSOLE##*.}"
  mdm_base="${CONSOLE%%.*}"
  mdm_device="/dev/${mdm_base}.${mdm_number}"
  true > "${mdm_device}A"
  true > "${mdm_device}B"
fi

# === Pilih firmware UEFI ===
if [ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ]; then
  LOADER="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
  log "Menggunakan UEFI firmware: BHYVE_UEFI.fd"
else
  LOADER=""
  log "UEFI firmware tidak ditemukan, menjalankan tanpa bootrom"
fi


# Jalankan bhyve
log "Starting VM '$VMNAME'..."

bhyve \
  -c "$CPUS" \
  -m "$MEMORY" \
  -AHP \
  -s 0,hostbridge \
  -s 3:0,virtio-blk,"$VM_DIR/$DISK" \
  -s 5:0,virtio-net,"$TAP" \
  -l com1,/dev/"${CONSOLE}A" \
  -s 31,lpc \
   $LOADER \
  "$VMNAME" >> "$LOG_FILE" 2>&1 &

BHYVE_PID=$!

# Tunggu sejenak ah
sleep 1

if ps -p "$BHYVE_PID" > /dev/null 2>&1; then
  log "VM '$VMNAME' telah running dengan PID $BHYVE_PID"
else
  log "Gagal menjalankan VM '$VMNAME' (PID tidak ditemukan)"
fi
