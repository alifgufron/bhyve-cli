#!/usr/local/bin/bash

# === Variabel dasar ===
BASEPATH="/home/admin/vm-bhvye"
VMNAME="$1"
VM_DIR="$BASEPATH/vm/$VMNAME"
CONF="$VM_DIR/vm.conf"
ISO_DIR="$BASEPATH/iso"
LOG_FILE="$VM_DIR/vm.log"

# === Fungsi logging dengan timestamp ===
log() {
  echo "[$(date '+%F %T')] [INFO] $1" | tee -a "$LOG_FILE"
}

# === Validasi input ===
if [ -z "$VMNAME" ]; then
  echo "Usage: $0 <vmname>"
  exit 1
fi

if [ ! -f "$CONF" ]; then
  echo "[ERROR] Konfigurasi $CONF tidak ditemukan"
  exit 1
fi

# === Load konfig ===
. "$CONF"

log "Start instalasi VM '$VMNAME'..."

# === Hentikan bhyve jika masih aktif ===
if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
  log "VM '$VMNAME' masih berjalan. Stopped..."
  pkill -f "bhyve.*$VMNAME"
  sleep 1
fi

# === Destroy jika masih tersisa di kernel ===
if bhyvectl --vm="$VMNAME" --destroy > /dev/null 2>&1; then
  log "VM '$VMNAME' sebelumnya masih ada nich di memori. OTW dihancurkan."
fi

# === Pilih sumber ISO ===
echo
echo "Pilih sumber ISO:"
echo "1. Pilih ISO yang sudah ada"
echo "2. Unduh ISO dari URL"
read -rp "Pilihan [1/2]: " CHOICE

case "$CHOICE" in
  1)
    log "Mencari file ISO di $ISO_DIR..."
    ISO_LIST=($(find "$ISO_DIR" -type f -name "*.iso" 2>/dev/null))
    if [ ${#ISO_LIST[@]} -eq 0 ]; then
      echo "[WARNING] Tidak ada file ISO ditemukan di $ISO_DIR nich!"
      exit 1
    fi
    echo "Daftar ISO tersedia:"
    select iso in "${ISO_LIST[@]}"; do
      if [ -n "$iso" ]; then
        ISO_PATH="$iso"
        break
      fi
    done
    ;;
  2)
    read -rp "Masukkan URL ISO: " ISO_URL
    ISO_FILE="$(basename "$ISO_URL")"
    ISO_PATH="$ISO_DIR/$ISO_FILE"
    mkdir -p "$ISO_DIR"
    log "Mengunduh ISO dari $ISO_URL"
    fetch "$ISO_URL" -o "$ISO_PATH" || {
      echo "[ERROR] Gagal mengunduh ISO"
      exit 1
    }
    ;;
  *)
    echo "[ERROR] Pilihan tidak valid"
    exit 1
    ;;
esac

# === Pilih firmware UEFI ===
if [ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ]; then
  LOADER="-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd"
  log "Menggunakan UEFI firmware: BHYVE_UEFI.fd"
else
  LOADER=""
  log "UEFI firmware tidak ditemukan, menjalankan tanpa bootrom"
fi

# === Jalankan bhyve di background ===
log "Menjalankan bhyve installer di background..."
bhyve \
  -c "$CPUS" \
  -m "$MEMORY" \
  -AHP \
  -s 0,hostbridge \
  -s 3:0,virtio-blk,"$VM_DIR/$DISK" \
  -s 4:0,ahci-cd,"$ISO_PATH" \
  -s 5:0,virtio-net,"$TAP" \
  -l com1,/dev/"${CONSOLE}A" \
  -s 31,lpc \
  $LOADER \
  "$VMNAME" >> "$LOG_FILE" 2>&1 &

VM_PID=$!
log "VM Bhyve dijalankan di background dengan PID $VM_PID"

# === Waiting device nmdmB muncul ===
for i in $(seq 1 10); do
  if [ -e "/dev/${CONSOLE}B" ]; then
    break
  fi
  sleep 0.5
done

# === Handler CTRL+C ===
cleanup() {
  echo
  echo "[INFO] SIGINT diterima, Stop paksa vm-bhyve (PID $VM_PID)..."
  kill "$VM_PID"

  sleep 1
  if ps -p "$VM_PID" > /dev/null 2>&1; then
   log "PID $VM_PID masih running, Proses KILL..."
   kill -9 "$VM_PID"
   sleep 1
  fi
  
  wait "$VM_PID"
  log "Installer untuk $VMNAME dipaksa stop oleh user wkwkwk"
  exit 0
}
trap cleanup INT

# === console otomatis ===
echo
echo ">>> Masuk ke console VM '$VMNAME' (keluar dengan ~.)"
cu -l /dev/"${CONSOLE}B"

# === Tunggu bhyve selesai ===
wait "$BHYVE_PID"
log "Installer untuk $VMNAME telah dihentikan (exit)"

echo
echo "Installer selesai. Jika instalasi OS berhasil, jalankan VM dengan:"
echo "  ./vm-start.sh $VMNAME"
