#!/bin/sh

# === Validasi input ===
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <vmname> <disksize in GB>"
  echo "Example:"
  echo "  $0 vm-bsd-acs 40"
  exit 1
fi

# === Variabel dasar ===
BASEPATH="/home/admin/vm-bhvye"
VMNAME="$1"
DISKSIZE="$2"
VM_DIR="$BASEPATH/vm/$VMNAME"
LOGFILE="$VM_DIR/vm.log"
CONF="$VM_DIR/vm.conf"
BRIDGE="bridge100"
mkdir -p "$VM_DIR"

# === Fungsi log dengan timestamp ===
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOGFILE"
}

log "Membuat VM $VMNAME di $VM_DIR"

# === Buat disk image ===
truncate -s "${DISKSIZE}G" "$VM_DIR/disk.img"
log "Disk ${DISKSIZE} GB dibuat: $VM_DIR/disk.img"

# === Buat UUID unik ===
UUID=$(uuidgen)

# === Generate MAC address unik (prefix static, suffix random) ===
MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"

# === Deteksi TAP berikutnya secara aman & create TAP ===
NEXT_TAP_NUM=0
while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
  NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
done
TAP="tap${NEXT_TAP_NUM}"

# === Create TAP interface
ifconfig "$TAP" create
log "TAP interface '$TAP' berhasil dibuat"

# === Add deskripsi TAP sesuai nama VM
ifconfig "$TAP" description "VM: $VMNAME"
log "Deskripsi TAP '$TAP' diset: VM: $VMNAME"

# === Aktifkan TAP
ifconfig "$TAP" up
log "TAP '$TAP' diaktifkan"

# === Tambahkan TAP ke bridge
ifconfig "$BRIDGE" addm "$TAP"
log "TAP '$TAP' ditambahkan ke bridge '$BRIDGE'"

# === Generate nama console unik ===
CONSOLE="nmdm-${VMNAME}.1"
log "Console device: $CONSOLE"

# === Buat file konfigurasi ===
cat > "$CONF" <<EOF
VMNAME=$VMNAME
UUID=$UUID
CPUS=2
MEMORY=2048M
TAP=$TAP
MAC=$MAC
BRIDGE=$BRIDGE
DISK=disk.img
CONSOLE=$CONSOLE
LOG=$LOGFILE
AUTOSTART=no
EOF

log "File konfigurasi dibuat: $CONF"
log "VM '$VMNAME' berhasil dibuat"
echo "Silakan lanjutkan dengan menjalankan: ./vm-install.sh $VMNAME"
