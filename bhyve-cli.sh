#!/usr/local/bin/bash

# === Pastikan script dijalankan dengan Bash ===
if [ -z "$BASH_VERSION" ]; then
  echo "[ERROR] Script ini membutuhkan Bash untuk berjalan. Harap jalankan dengan 'bash <nama_script>' atau pastikan shell Anda adalah Bash." >&2
  exit 1
fi

# === Variabel dasar global ===
BASEPATH="/home/admin/vm-bhvye"
ISO_DIR="$BASEPATH/iso"
#BRIDGE="bridge100"

# === Fungsi log dengan timestamp ===
log() {
  # Log messages will be written to the VM's specific log file if available,
  # otherwise to stderr.
  if [ -n "$LOG_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >&2
  fi
}

# === Fungsi untuk memuat konfigurasi VM ===
load_vm_config() {
  VMNAME="$1"
  VM_DIR="$BASEPATH/vm/$VMNAME"
  CONF_FILE="$VM_DIR/vm.conf"

  if [ ! -f "$CONF_FILE" ]; then
    echo "[ERROR] Konfigurasi VM '$VMNAME' tidak ditemukan: $CONF_FILE"
    exit 1
  fi
  . "$CONF_FILE"
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE after loading config
}

# === Subcommand: switch add ===
cmd_switch_add() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo " "
    echo "Usage: $0 switch add <bridge_name> <physical_interface> [vlan_tag]"
    echo "Example:"
    echo "  $0 switch add bridge0 em0"
    echo "  $0 switch add bridge1 em1 100  (untuk VLAN ID 100)"
    echo " "
    exit 1
  fi

  BRIDGE_NAME="$1"
  PHYS_IF="$2"
  VLAN_TAG="$3"

  log "Memeriksa interface fisik '$PHYS_IF'..."
  if ! ifconfig "$PHYS_IF" > /dev/null 2>&1; then
    echo "[ERROR] Interface fisik '$PHYS_IF' tidak ditemukan."
    exit 1
  fi

  MEMBER_IF="$PHYS_IF"
  if [ -n "$VLAN_TAG" ]; then
    VLAN_IF="vlan${VLAN_TAG}"
    log "Membuat interface VLAN '$VLAN_IF'..."
    ifconfig "$VLAN_IF" create
    if [ $? -ne 0 ]; then
      echo "[ERROR] Gagal membuat interface VLAN '$VLAN_IF'."
      exit 1
    fi
    log "Mengkonfigurasi '$VLAN_IF' dengan tag '$VLAN_TAG' di atas '$PHYS_IF'..."
    ifconfig "$VLAN_IF" vlan "$VLAN_TAG" vlandev "$PHYS_IF"
    if [ $? -ne 0 ]; then
      echo "[ERROR] Gagal mengkonfigurasi interface VLAN '$VLAN_IF'."
      exit 1
    fi
    log "Interface VLAN '$VLAN_IF' berhasil dikonfigurasi."
    MEMBER_IF="$VLAN_IF"
  fi

  log "Memeriksa bridge '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    log "Bridge interface '$BRIDGE_NAME' belum ada. Membuat..."
    ifconfig bridge create name "$BRIDGE_NAME"
    if [ $? -ne 0 ]; then
      echo "[ERROR] Gagal membuat bridge '$BRIDGE_NAME'."
      exit 1
    fi
    log "Bridge interface '$BRIDGE_NAME' berhasil dibuat."
  else
    log "Bridge interface '$BRIDGE_NAME' sudah ada."
  fi

  log "Menambahkan '$MEMBER_IF' ke bridge '$BRIDGE_NAME'..."
  ifconfig "$BRIDGE_NAME" addm "$MEMBER_IF"
  if [ $? -ne 0 ]; then
    echo "[ERROR] Gagal menambahkan '$MEMBER_IF' ke bridge '$BRIDGE_NAME'."
    exit 1
  fi
  log "Interface '$MEMBER_IF' berhasil ditambahkan ke bridge '$BRIDGE_NAME'."
  echo "Bridge '$BRIDGE_NAME' sekarang memiliki member '$MEMBER_IF'."
}

# === Subcommand: switch list ===
cmd_switch_list() {
  echo "Daftar Bridge Interfaces:"
  BRIDGES=$(ifconfig -l | tr ' ' '\n' | grep '^bridge')

  if [ -z "$BRIDGES" ]; then
    echo "Tidak ada bridge interface yang ditemukan."
    return
  fi

  for BRIDGE_IF in $BRIDGES; do
    echo "----------------------------------------"
    echo "Bridge: $BRIDGE_IF"
    MEMBERS=$(ifconfig "$BRIDGE_IF" | grep 'member:' | awk '{print $2}')
    if [ -n "$MEMBERS" ]; then
      echo "  Members:"
      for MEMBER in $MEMBERS; do
        echo "    - $MEMBER"
      done
    else
      echo "  Tidak ada member."
    fi
  done
  echo "----------------------------------------"
}

# === Subcommand: switch remove ===
cmd_switch_remove() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 switch remove <bridge_name> <physical_interface> [vlan_tag]"
    echo "Example:"
    echo "  $0 switch remove bridge0 em0"
    echo "  $0 switch remove bridge1 em1 100  (untuk VLAN ID 100)"
    exit 1
  fi

  BRIDGE_NAME="$1"
  PHYS_IF="$2"
  VLAN_TAG="$3"

  log "Memeriksa bridge '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" > /dev/null 2>&1; then
    echo "[ERROR] Bridge '$BRIDGE_NAME' tidak ditemukan."
    exit 1
  fi

  MEMBER_IF="$PHYS_IF"
  if [ -n "$VLAN_TAG" ]; then
    MEMBER_IF="vlan${VLAN_TAG}"
  fi

  log "Memeriksa apakah '$MEMBER_IF' adalah member dari '$BRIDGE_NAME'..."
  if ! ifconfig "$BRIDGE_NAME" | grep -qw "$MEMBER_IF"; then
    echo "[ERROR] Interface '$MEMBER_IF' bukan member dari bridge '$BRIDGE_NAME'."
    exit 1
  fi

  log "Menghapus '$MEMBER_IF' dari bridge '$BRIDGE_NAME'..."
  ifconfig "$BRIDGE_NAME" deletem "$MEMBER_IF"
  if [ $? -ne 0 ]; then
    echo "[ERROR] Gagal menghapus '$MEMBER_IF' dari bridge '$BRIDGE_NAME'."
    exit 1
  fi
  log "Interface '$MEMBER_IF' berhasil dihapus dari bridge '$BRIDGE_NAME'."

  if [ -n "$VLAN_TAG" ]; then
    log "Menghancurkan interface VLAN '$MEMBER_IF'..."
    ifconfig "$MEMBER_IF" destroy
    if [ $? -ne 0 ]; then
      echo "[ERROR] Gagal menghancurkan interface VLAN '$MEMBER_IF'."
      exit 1
    fi
    log "Interface VLAN '$MEMBER_IF' berhasil dihancurkan."
  fi

  # Cek apakah bridge kosong setelah penghapusan
  MEMBERS=$(ifconfig "$BRIDGE_NAME" | grep 'member:' | awk '{print $2}')
  if [ -z "$MEMBERS" ]; then
    read -rp "Bridge '$BRIDGE_NAME' sekarang kosong. Hapus bridge ini juga? (y/n): " CONFIRM_DESTROY
    if [[ "$CONFIRM_DESTROY" =~ ^[Yy]$ ]]; then
      log "Menghapus bridge '$BRIDGE_NAME'..."
      ifconfig "$BRIDGE_NAME" destroy
      if [ $? -ne 0 ]; then
        echo "[ERROR] Gagal menghapus bridge '$BRIDGE_NAME'."
        exit 1
      fi
      log "Bridge '$BRIDGE_NAME' berhasil dihapus."
    else
      log "Bridge '$BRIDGE_NAME' tidak dihapus."
    fi
  else
    echo "Bridge '$BRIDGE_NAME' masih memiliki member."
  fi
}

# === Subcommand: create ===
cmd_create() {
  if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 create <vmname> <disksize in GB> <bridge_name>"
    echo "Example:"
    echo "  $0 create vm-bsd 40 bridge100"
    exit 1
  fi

  VMNAME="$1"
  DISKSIZE="$2"
  VM_BRIDGE="$3"
  VM_DIR="$BASEPATH/vm/$VMNAME"
  CONF="$VM_DIR/vm.conf"

  mkdir -p "$VM_DIR"
  LOG_FILE="$VM_DIR/vm.log" # Set LOG_FILE for create command

  log "Membuat VM $VMNAME di $VM_DIR"

  # === Cek dan buat bridge interface jika belum ada ===
  if ! ifconfig "$VM_BRIDGE" > /dev/null 2>&1; then
    log "Bridge interface '$VM_BRIDGE' belum ada. Membuat..."
    ifconfig bridge create name "$VM_BRIDGE"
    log "Bridge interface '$VM_BRIDGE' berhasil dibuat."
  else
    log "Bridge interface '$VM_BRIDGE' sudah ada."
  fi

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
  ifconfig "$TAP" description "vmnet/${VMNAME}/0/${VM_BRIDGE}"
  log "Deskripsi TAP '$TAP' diset: VM: vmnet/${VMNAME}/0/${VM_BRIDGE}"

  # === Aktifkan TAP
  ifconfig "$TAP" up
  log "TAP '$TAP' diaktifkan"

  # === Tambahkan TAP ke bridge
  ifconfig "$VM_BRIDGE" addm "$TAP"
  log "TAP '$TAP' ditambahkan ke bridge '$VM_BRIDGE'"

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
BRIDGE=$VM_BRIDGE
DISK=disk.img
CONSOLE=$CONSOLE
LOG=$LOG_FILE
AUTOSTART=no
EOF

  log "File konfigurasi dibuat: $CONF"
  log "VM '$VMNAME' berhasil dibuat"
  echo "Silakan lanjutkan dengan menjalankan: $0 install $VMNAME"
}

# === Subcommand: delete ===
cmd_delete() {
  if [ -z "$1" ]; then
    echo "Usage: $0 delete <vmname>"
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

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
}

# === Subcommand: install ===
cmd_install() {
  if [ -z "$1" ]; then
    echo "Usage: $0 install <vmname>"
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

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
  wait "$VM_PID" # Changed from BHYVE_PID to VM_PID
  log "Installer untuk $VMNAME telah dihentikan (exit)"

  echo
  echo "Installer selesai. Jika instalasi OS berhasil, jalankan VM dengan:"
  echo "  $0 start $VMNAME"
}

# === Subcommand: start ===
cmd_start() {
  if [ -z "$1" ]; then
    echo "Usage: $0 start <vmname>"
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

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
    log "TAP '$TAP' ditambahkan ke bridge '$BRIDGE"
  else
    log "TAP '$TAP' sudah terhubung ke bridge '$BRIDGE"
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
}

# === Subcommand: stop ===
cmd_stop() {
  if [ -z "$1" ]; then
    echo "Usage: $0 stop <vmname>"
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  log "Stopped VM '$VMNAME'..."

  # === Cek PID dari proses aktif
  VM_PID=$(pgrep -f "bhyve.*$VMNAME")

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

  log "VM '$VMNAME' berhasil Stop."
}

# === Subcommand: console ===
cmd_console() {
  if [ -z "$1" ]; then
    echo "Usage: $0 console <vmname>"
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

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
}

# === Subcommand: logs ===
cmd_logs() {
  if [ -z "$1" ]; then
    echo "Usage: $0 logs <vmname>"
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  if [ ! -f "$LOG_FILE" ]; then
    echo "[ERROR] Log file for VM '$VMNAME' not found: $LOG_FILE"
    exit 1
  fi

  echo ">>> Displaying logs for VM '$VMNAME' (Press Ctrl+C to exit)"
  tail -f "$LOG_FILE"
}

# === Subcommand: status ===
cmd_status() {
  local header_format="%-20s %-10s %-17s %-20s %-12s %-12s %-12s %-12s %-10s %-10s\n"
  local header_line
  printf "$header_format" \
    "VM NAME" \
    "STATUS" \
    "MAC ADDRESS" \
    "BRIDGE" \
    "CPU (Set)" \
    "RAM (Set)" \
    "CPU Usage" \
    "RAM Usage" \
    "TAP" \
    "PID"
  
  # Generate dynamic separator line
  header_line=$(printf "$header_format" \
    "--------------------" \
    "----------" \
    "-----------------" \
    "--------------------" \
    "------------" \
    "------------" \
    "------------" \
    "------------" \
    "----------" \
    "----------")
  echo "${header_line// /}" # Remove spaces to make it a continuous line

  for VMCONF in "$BASEPATH"/vm/*/vm.conf; do
    [ -f "$VMCONF" ] || continue
    . "$VMCONF"

    local VMNAME="${VMNAME:-N/A}"
    local MAC="${MAC:-N/A}"
    local BRIDGE="${BRIDGE:-N/A}"
    local CPUS="${CPUS:-N/A}"
    local MEMORY="${MEMORY:-N/A}"
    local TAP="${TAP:-N/A}"

    local PID=$(pgrep -f "bhyve.*$VMNAME")
    local CPU_USAGE="N/A"
    local RAM_USAGE="N/A"

    if [ -n "$PID" ]; then
      local STATUS="RUNNING"
      # Get CPU and Memory usage for the bhyve process
      # %cpu: CPU usage, rss: resident set size in KB
      local PS_INFO=$(ps -p "$PID" -o %cpu,rss= | tail -n 1)
      
      if [ -n "$PS_INFO" ]; then
        CPU_USAGE=$(echo "$PS_INFO" | awk '{print $1 "%"}')
        local RAM_RSS_KB=$(echo "$PS_INFO" | awk '{print $2}')
        
        if command -v bc >/dev/null 2>&1; then
          RAM_USAGE=$(echo "scale=0; $RAM_RSS_KB / 1024" | bc) # Convert KB to MB
          RAM_USAGE="${RAM_USAGE}MB"
        else
          RAM_USAGE="${RAM_RSS_KB}KB (bc not found)"
        fi
      fi
    else
      local STATUS="STOPPED"
      local PID="-"
    fi

    printf "$header_format" "$VMNAME" "$STATUS" "$MAC" "$BRIDGE" "$CPUS" "$MEMORY" "$CPU_USAGE" "$RAM_USAGE" "$TAP" "$PID"
  done
}

# === Subcommand: autostart ===
cmd_autostart() {
  if [ -z "$1" ] || ( [ "$2" != "enable" ] && [ "$2" != "disable" ] ); then
    echo "Usage: $0 autostart <vmname> <enable|disable>"
    exit 1
  fi

  VMNAME="$1"
  ACTION="$2"
  load_vm_config "$VMNAME"

  local CONF_FILE="$VM_DIR/vm.conf"

  if [ "$ACTION" = "enable" ]; then
    log "Enabling autostart for VM '$VMNAME'..."
    sed -i '' 's/^AUTOSTART=.*/AUTOSTART=yes/' "$CONF_FILE"
    log "Autostart enabled for VM '$VMNAME'."
  elif [ "$ACTION" = "disable" ]; then
    log "Disabling autostart for VM '$VMNAME'..."
    sed -i '' 's/^AUTOSTART=.*/AUTOSTART=no/' "$CONF_FILE"
    log "Autostart disabled for VM '$VMNAME'."
  fi
}

# === Subcommand: modify ===
cmd_modify() {
  if [ -z "$1" ]; then
    echo "Usage: $0 modify <vmname> [--cpu <num>] [--ram <size>] [--tap <tap_name>] [--bridge <bridge_name>]"
    echo "Example:"
    echo "  $0 modify myvm --cpu 4 --ram 4096M"
    echo "  $0 modify myvm --tap tap1 --bridge bridge1"
    exit 1
  fi

  VMNAME="$1"
  shift
  load_vm_config "$VMNAME"

  local CONF_FILE="$VM_DIR/vm.conf"
  local CPU_NEW=""
  local RAM_NEW=""
  local TAP_NEW=""
  local BRIDGE_NEW=""

  # Check if VM is running
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    echo "[ERROR] VM '$VMNAME' is currently running. Please stop the VM before modifying its configuration."
    exit 1
  fi

  while (( "$#" )); do
    case "$1" in
      --cpu)
        shift
        CPU_NEW="$1"
        log "Setting CPU to $CPU_NEW for VM '$VMNAME'."
        sed -i '' "s/^CPUS=.*/CPUS=$CPU_NEW/" "$CONF_FILE"
        ;;
      --ram)
        shift
        RAM_NEW="$1"
        log "Setting RAM to $RAM_NEW for VM '$VMNAME'."
        sed -i '' "s/^MEMORY=.*/MEMORY=$RAM_NEW/" "$CONF_FILE"
        ;;
      --tap)
        shift
        TAP_NEW="$1"
        log "Setting TAP interface to $TAP_NEW for VM '$VMNAME'."
        sed -i '' "s/^TAP=.*/TAP=$TAP_NEW/" "$CONF_FILE"
        ;;
      --bridge)
        shift
        BRIDGE_NEW="$1"
        log "Setting BRIDGE to $BRIDGE_NEW for VM '$VMNAME'."
        sed -i '' "s/^BRIDGE=.*/BRIDGE=$BRIDGE_NEW/" "$CONF_FILE"
        ;;
      *)
        echo "[ERROR] Invalid option: $1"
        echo "Usage: $0 modify <vmname> [--cpu <num>] [--ram <size>] [--tap <tap_name>] [--bridge <bridge_name>]"
        exit 1
        ;;
    esac
    shift
  done

  log "VM '$VMNAME' configuration updated."
}

# === Subcommand: clone ===
cmd_clone() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 clone <source_vmname> <new_vmname>"
    echo "Example:"
    echo "  $0 clone myvm newvm"
    exit 1
  fi

  SOURCE_VMNAME="$1"
  NEW_VMNAME="$2"

  SOURCE_VM_DIR="$BASEPATH/vm/$SOURCE_VMNAME"
  NEW_VM_DIR="$BASEPATH/vm/$NEW_VMNAME"

  # Check if source VM exists
  if [ ! -d "$SOURCE_VM_DIR" ]; then
    echo "[ERROR] Source VM '$SOURCE_VMNAME' not found: $SOURCE_VM_DIR"
    exit 1
  fi

  # Check if new VM already exists
  if [ -d "$NEW_VM_DIR" ]; then
    echo "[ERROR] Destination VM '$NEW_VM_NAME' already exists: $NEW_VM_DIR"
    exit 1
  fi

  # Load source VM config to get its status
  load_vm_config "$SOURCE_VMNAME"

  # Check if source VM is running
  if pgrep -f "bhyve.*$SOURCE_VMNAME" > /dev/null; then
    echo "[ERROR] Source VM '$SOURCE_VMNAME' is currently running. Please stop the VM before cloning."
    exit 1
  fi

  log "Cloning VM '$SOURCE_VMNAME' to '$NEW_VMNAME'..."

  # Create new VM directory
  mkdir -p "$NEW_VM_DIR"
  log "Created new VM directory: $NEW_VM_DIR"

  # Copy disk image
  log "Copying disk image from $SOURCE_VM_DIR/disk.img to $NEW_VM_DIR/disk.img..."
  cp "$SOURCE_VM_DIR/disk.img" "$NEW_VM_DIR/disk.img"
  if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to copy disk image."
    rm -rf "$NEW_VM_DIR"
    exit 1
  fi
  log "Disk image copied."

  # Generate new UUID, MAC, TAP, CONSOLE
  NEW_UUID=$(uuidgen)
  NEW_MAC="58:9c:fc$(jot -r -w ":%02x" -s "" 3 0 255)"
  
  NEXT_TAP_NUM=0
  while ifconfig | grep -q "^tap${NEXT_TAP_NUM}:"; do
    NEXT_TAP_NUM=$((NEXT_TAP_NUM + 1))
  done
  NEW_TAP="tap${NEXT_TAP_NUM}"

  NEW_CONSOLE="nmdm-${NEW_VMNAME}.1"

  # Create new vm.conf
  NEW_CONF_FILE="$NEW_VM_DIR/vm.conf"
  cat > "$NEW_CONF_FILE" <<EOF
VMNAME=$NEW_VMNAME
UUID=$NEW_UUID
CPUS=$CPUS
MEMORY=$MEMORY
TAP=$NEW_TAP
MAC=$NEW_MAC
BRIDGE=$BRIDGE
DISK=disk.img
CONSOLE=$NEW_CONSOLE
LOG=$NEW_VM_DIR/vm.log
AUTOSTART=no
EOF

  log "New configuration file created: $NEW_CONF_FILE"
  log "VM '$NEW_VMNAME' cloned successfully."
  echo "VM '$NEW_VMNAME' has been cloned from '$SOURCE_VMNAME'."
  echo "You can now start it with: $0 start $NEW_VMNAME"
}

# === Subcommand: info ===
cmd_info() {
  if [ -z "$1" ]; then
    echo "Usage: $0 info <vmname>"
    exit 1
  fi

  VMNAME="$1"
  load_vm_config "$VMNAME"

  echo "----------------------------------------"
  echo "VM Information for '$VMNAME':"
  echo "----------------------------------------"
  local info_format="  %-15s: %s\n"
  printf "$info_format" "Name" "$VMNAME"
  printf "$info_format" "UUID" "$UUID"
  printf "$info_format" "CPUs" "$CPUS"
  printf "$info_format" "Memory" "$MEMORY"
  printf "$info_format" "Disk" "$VM_DIR/$DISK"
  local DISK_USAGE="N/A"
  if [ -f "$VM_DIR/$DISK" ]; then
    DISK_USAGE=$(du -h "$VM_DIR/$DISK" | awk '{print $1}')
  fi
  printf "$info_format" "Disk Usage" "$DISK_USAGE"
  printf "$info_format" "TAP" "$TAP"
  printf "$info_format" "MAC" "$MAC"
  printf "$info_format" "Bridge" "$BRIDGE"
  printf "$info_format" "Console" "$CONSOLE"
  printf "$info_format" "Log File" "$LOG_FILE"
  printf "$info_format" "Autostart" "$AUTOSTART"

  # Check runtime status
  local PID=$(pgrep -f "bhyve.*$VMNAME")
  if [ -n "$PID" ]; then
    printf "$info_format" "Status" "RUNNING (PID: $PID)"
    local PS_INFO=$(ps -p "$PID" -o %cpu,rss= | tail -n 1)
    if [ -n "$PS_INFO" ]; then
      local CPU_USAGE=$(echo "$PS_INFO" | awk '{print $1 "%"}')
      local RAM_RSS_KB=$(echo "$PS_INFO" | awk '{print $2}')
      local RAM_USAGE
      if command -v bc >/dev/null 2>&1; then
        RAM_USAGE=$(echo "scale=0; $RAM_RSS_KB / 1024" | bc) # Convert KB to MB
        RAM_USAGE="${RAM_USAGE}MB"
      else
        RAM_USAGE="${RAM_RSS_KB}KB (bc not found)"
      fi
      printf "$info_format" "CPU Usage" "$CPU_USAGE"
      printf "$info_format" "RAM Usage" "$RAM_USAGE"
    fi
  else
    printf "$info_format" "Status" "STOPPED"
  fi
  echo "----------------------------------------"
}

# === Subcommand: resize-disk ===
cmd_resize_disk() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 resize-disk <vmname> <new_size_in_GB>"
    echo "Example:"
    echo "  $0 resize-disk myvm 60"
    exit 1
  fi

  VMNAME="$1"
  NEW_SIZE_GB="$2"
  load_vm_config "$VMNAME"

  local DISK_PATH="$VM_DIR/$DISK"

  # Check if VM is running
  if pgrep -f "bhyve.*$VMNAME" > /dev/null; then
    echo "[ERROR] VM '$VMNAME' is currently running. Please stop the VM before resizing its disk."
    exit 1
  fi

  if [ ! -f "$DISK_PATH" ]; then
    echo "[ERROR] Disk image for VM '$VMNAME' not found: $DISK_PATH"
    exit 1
  fi

  # Get current disk size in GB
  CURRENT_SIZE_BYTES=$(stat -f %z "$DISK_PATH")
  CURRENT_SIZE_GB=$((CURRENT_SIZE_BYTES / 1024 / 1024 / 1024))

  if (( NEW_SIZE_GB <= CURRENT_SIZE_GB )); then
    echo "[ERROR] New size ($NEW_SIZE_GB GB) must be greater than current size ($CURRENT_SIZE_GB GB)."
    exit 1
  fi

  log "Resizing disk for VM '$VMNAME' from ${CURRENT_SIZE_GB}GB to ${NEW_SIZE_GB}GB..."
  truncate -s "${NEW_SIZE_GB}G" "$DISK_PATH"
  if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to resize disk image."
    exit 1
  fi
  log "Disk resized successfully."
  echo "Disk for VM '$VMNAME' has been resized to ${NEW_SIZE_GB}GB."
  echo "Note: You may need to extend the partition inside the VM operating system."
}

# === Main logic ===
case "$1" in
  create)
    shift
    cmd_create "$@"
    ;;
  delete)
    shift
    cmd_delete "$@"
    ;;
  install)
    shift
    cmd_install "$@"
    ;;
  start)
    shift
    cmd_start "$@"
    ;;
  stop)
    shift
    cmd_stop "$@"
    ;;
  console)
    shift
    cmd_console "$@"
    ;;
  logs)
    shift
    cmd_logs "$@"
    ;;
  status)
    shift
    cmd_status "$@"
    ;;
  autostart)
    shift
    cmd_autostart "$@"
    ;;
  modify)
    shift
    cmd_modify "$@"
    ;;
  clone)
    shift
    cmd_clone "$@"
    ;;
  info)
    shift
    cmd_info "$@"
    ;;
  resize-disk)
    shift
    cmd_resize_disk "$@"
    ;;
  switch)
    shift
    case "$1" in
      add)
        shift
        cmd_switch_add "$@"
        ;;
      list)
        shift
        cmd_switch_list "$@"
        ;;
      remove)
        shift
        cmd_switch_remove "$@"
        ;;
      *)
        echo " "
        echo "Invalid subcommand: $1"
        echo " "
        echo "Usage: $0 switch <add|list|remove> [arguments]"
        echo "  add <bridge_name> <physical_interface>    - Create a bridge and add a physical interface"
        echo "  list                                      - List all bridge interfaces and their members"
        echo "  remove <bridge_name> <physical_interface> - Remove a physical interface from a bridge"
        echo " "
        exit 1
        ;;
    esac
    ;;
  *)
    echo " "
    echo "Invalid comand: $1"
    echo " "
    echo "Usage: $0 <command> [arguments]"
    echo "Commands:"
    echo "  create <vmname> <disksize in GB> <bridge name>  - Create a new VM"
    echo "  delete <vmname>                                 - Delete a VM"
    echo "  install <vmname>                                - Install OS on a VM"
    echo "  start <vmname>                                  - Start a VM"
    echo "  stop <vmname>                                   - Stop a VM"
    echo "  console <vmname>                                - Access VM console"
    echo "  logs <vmname>                                   - Display VM logs"
    echo "  autostart <vmname> <enable|disable>             - Enable/disable VM autostart"
    echo "  modify <vmname> [options]                       - Modify VM configuration (CPU, RAM, etc.)"
    echo "  clone <source_vmname> <new_vmname>              - Clone an existing VM"
    echo "  info <vmname>                                   - Display detailed information about a VM"
    echo "  resize-disk <vmname> <new_size_in_GB>           - Resize a VM's disk image (only supports increasing size)"
    echo "  status                                          - Show status of all VMs"
    echo "  switch <add|list|remove>                        - Manage network bridges"
    echo " "
    exit 1
    ;;
esac
