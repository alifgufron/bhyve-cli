#!/bin/sh
#
# simple-bhyve-vm-nmdm.sh - Script sederhana untuk mengelola VM FreeBSD dengan bhyve
#
# Cara Penggunaan:
#   1. Pastikan Anda memiliki hak akses root (jalankan dengan sudo).
#   2. Pastikan modul kernel vmm.ko dan nmdm.ko sudah dimuat.
#      sudo kldload vmm
#      sudo kldload nmdm
#   3. Buat tap device jika belum ada: sudo ifconfig tap0 create
#   4. Jalankan script dengan mode 'install' atau 'run':
#      sudo sh simple-bhyve-vm-nmdm.sh install
#      sudo sh simple-bhyve-vm-nmdm.sh run
#
#   Untuk keluar dari konsol stdio (mode install): Matikan guest OS atau tekan Ctrl+C di terminal host.
#   Untuk keluar dari konsol nmdm (mode run): Ctrl+a lalu c (di jendela cu).
#

# --- KONFIGURASI VM ---
VM_NAME="my-freebsd-vm-2"
MEM_SIZE="1G"       # Ukuran memori VM (misal: 1G, 2048M)
NUM_CPUS="2"        # Jumlah CPU virtual
TAP_DEV="tap0"      # Nama tap device untuk jaringan
CONSOLE_NMDM_DEV="/dev/nmdm-my-freebsd-vm.1" # Konsol nmdm untuk mode 'run'

# Path ke file disk virtual VM Anda (akan dibuat jika belum ada)
DISK_IMG="/home/admin/vm-bhvye/script/${VM_NAME}.img"
# Path ke file ISO installer FreeBSD (hanya untuk mode 'install')
ISO_PATH="/home/admin/vm-bhvye/iso/FreeBSD-14.3-RELEASE-amd64-dvd1.iso" # GANTI DENGAN PATH ISO ANDA!

# --- LOKASI BINARI BHYVE ---
BHYVELOAD="/usr/sbin/bhyveload"
BHYVECTL="/usr/sbin/bhyvectl"
BHYVE="/usr/sbin/bhyve"

# --- FUNGSI BANTUAN ---
errmsg() {
    echo "ERROR: $1" >&2
    exit 1
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        errmsg "Script ini harus dijalankan dengan hak akses superuser (root)."
    fi
}

check_kld() {
    kldstat -n "$1" > /dev/null 2>&1 || errmsg "Modul kernel '$1.ko' tidak dimuat. Jalankan 'sudo kldload $1'."
}

destroy_vm() {
    echo "Menghancurkan VM '$VM_NAME' jika sedang berjalan..."
    ${BHYVECTL} --vm="${VM_NAME}" --destroy > /dev/null 2>&1
}

create_disk_if_not_exists() {
    if [ ! -f "$DISK_IMG" ]; then
        echo "File disk '$DISK_IMG' tidak ditemukan. Membuat disk 20G..."
        truncate -s 20G "$DISK_IMG" || errmsg "Gagal membuat file disk '$DISK_IMG'."
    fi
}

ensure_nmdm_device_exists() {
    local console_path="$1"
    if [[ "$console_path" == "/dev/nmdm"* ]]; then
        local base_nmdm_name="${console_path}" # e.g., /dev/nmdm0
        if ! [ -e "${base_nmdm_name}A" ] || ! [ -e "${base_nmdm_name}B" ]; then
            errmsg "Perangkat konsol nmdm (${base_nmdm_name}A atau ${base_nmdm_name}B) tidak ditemukan. Pastikan modul kernel nmdm.ko dimuat dan Anda memiliki izin yang sesuai."
        fi
    fi
}

# --- FUNGSI UTAMA ---

run_install_mode() {
    echo "--- Memulai Instalasi FreeBSD untuk VM '$VM_NAME' ---"

    # Periksa ISO
    [ ! -f "$ISO_PATH" ] && errmsg "File ISO installer tidak ditemukan: '$ISO_PATH'. Harap perbarui variabel ISO_PATH."

    # Buat disk jika belum ada
    create_disk_if_not_exists

    # Hancurkan VM lama jika ada
    destroy_vm

    echo "1. Memuat installer dengan bhyveload (konsol: stdio)..."
    ${BHYVELOAD} -m "${MEM_SIZE}" -d "${ISO_PATH}" -c stdio "${VM_NAME}" || errmsg "bhyveload gagal."

    echo "2. Menjalankan VM dengan bhyve untuk instalasi (konsol: stdio)..."
    ${BHYVE} -c "${NUM_CPUS}" -m "${MEM_SIZE}" -H -A -P \
        -s 0:0,hostbridge \
        -s 1:0,lpc \
        -s 2:0,virtio-net,"${TAP_DEV}" \
        -s 3:0,virtio-blk,"${DISK_IMG}" \
        -l com1,stdio \
        -s 31:0,ahci-cd,"${ISO_PATH}" \
        "${VM_NAME}"

    BHYVE_EXIT_CODE=$?
    if [ ${BHYVE_EXIT_CODE} -ne 0 ]; then
        echo "Peringatan: bhyve keluar dengan kode status ${BHYVE_EXIT_CODE}."
    fi

    echo "Instalasi selesai atau VM dimatikan. Membersihkan..."
    destroy_vm
}

run_vm_mode() {
    echo "--- Menjalankan VM FreeBSD '$VM_NAME' dari disk ---"

    # Periksa apakah file disk ada
    [ ! -f "$DISK_IMG" ] && errmsg "File disk VM '$DISK_IMG' tidak ditemukan. Harap instal OS terlebih dahulu atau periksa path."

    # Hancurkan VM lama jika ada
    destroy_vm

    # Pastikan perangkat nmdm ada
    ensure_nmdm_device_exists "${CONSOLE_NMDM_DEV}"

    echo "1. Memuat bootloader dari disk dengan bhyveload (konsol: stdio)..."
    ${BHYVELOAD} -m "${MEM_SIZE}" -d "${DISK_IMG}" -c stdio "${VM_NAME}" || errmsg "bhyveload gagal."

    echo "2. Menjalankan VM dengan bhyve (konsol: nmdm)..."
    # bhyve berjalan di latar belakang, konsolnya di nmdm
    ${BHYVE} -c "${NUM_CPUS}" -m "${MEM_SIZE}" -H -A -P \
        -s 0:0,hostbridge \
        -s 1:0,lpc \
        -s 2:0,virtio-net,"${TAP_DEV}" \
        -s 3:0,virtio-blk,"${DISK_IMG}" \
        -l com1,"${CONSOLE_NMDM_DEV}A" \
        "${VM_NAME}" & # Jalankan di latar belakang
    BHYVE_PID=$!
    echo "VM '$VM_NAME' dimulai dengan PID: $BHYVE_PID"
    echo "Meluncurkan 'cu' untuk terhubung ke konsol VM..."
    cu -l "${CONSOLE_NMDM_DEV}B" || errmsg "Gagal meluncurkan cu. Pastikan cu terinstal dan ${CONSOLE_NMDM_DEV}B tersedia."
    echo "Konsol 'cu' ditutup. Menunggu VM dimatikan..."
    wait $BHYVE_PID # Tunggu sampai VM dimatikan

    echo "VM dimatikan. Membersihkan..."
    destroy_vm
}

# --- EKSEKUSI SCRIPT ---
check_root
check_kld "vmm"

case "$1" in
    install)
        run_install_mode
        ;;
    run)
        check_kld "nmdm" # nmdm.ko diperlukan untuk mode 'run'
        run_vm_mode
        ;;
    *)
        echo "Penggunaan: sudo sh $0 [install|run]"
        echo "  install: Untuk menginstal FreeBSD dari ISO ke disk virtual (konsol: stdio)."
        echo "  run:     Untuk menjalankan VM FreeBSD yang sudah terinstal dari disk virtual (konsol: nmdm)."
        exit 1
        ;;
esac
