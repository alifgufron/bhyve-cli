# Dokumentasi simple-bhyve-vm-nmdm.sh

Skrip `simple-bhyve-vm-nmdm.sh` adalah alat sederhana berbasis shell untuk mengelola mesin virtual (VM) FreeBSD menggunakan hypervisor bhyve di FreeBSD. Skrip ini dirancang untuk memberikan fleksibilitas dalam penggunaan konsol, dengan mode instalasi menggunakan `stdio` dan mode menjalankan VM menggunakan perangkat `nmdm` untuk koneksi konsol terpisah.

## Daftar Isi
1.  [Prasyarat](#prasyarat)
2.  [Cara Penggunaan](#cara-penggunaan)
    *   [Mode Instalasi (`install`)](#mode-instalasi-install)
    *   [Mode Jalankan (`run`)](#mode-jalankan-run)
3.  [Konfigurasi](#konfigurasi)
4.  [Fungsi Bantuan](#fungsi-bantuan)
5.  [Fungsi Utama](#fungsi-utama)
6.  [Keluar dari Konsol VM](#keluar-dari-konsol-vm)
7.  [Pemecahan Masalah](#pemecahan-masalah)

## 1. Prasyarat
Sebelum menjalankan skrip ini, pastikan prasyarat berikut terpenuhi:

*   **Hak Akses Root:** Skrip harus dijalankan dengan hak akses superuser (`sudo`).
*   **Modul Kernel bhyve:** Modul kernel `vmm.ko` harus dimuat. Anda dapat memuatnya dengan:
    ```bash
    sudo kldload vmm
    ```
*   **Modul Kernel nmdm:** Untuk mode `run`, modul kernel `nmdm.ko` harus dimuat. Anda dapat memuatnya dengan:
    ```bash
    sudo kldload nmdm
    ```
*   **Perangkat TAP:** Perangkat jaringan virtual TAP (misalnya `tap0`) harus dibuat dan dikonfigurasi. Jika belum ada, buatlah dengan:
    ```bash
    sudo ifconfig tap0 create
    ```
    Anda mungkin juga perlu mengkonfigurasi bridge jika ingin VM memiliki akses jaringan eksternal.
*   **File ISO FreeBSD (untuk mode `install`):** Anda memerlukan file ISO installer FreeBSD (misalnya `FreeBSD-14.3-RELEASE-amd64-dvd1.iso`). Pastikan jalur ke file ini dikonfigurasi dengan benar di variabel `ISO_PATH`.
*   **Utilitas bhyve:** Utilitas `bhyveload`, `bhyvectl`, dan `bhyve` harus terinstal dan tersedia di `/usr/sbin/`.
*   **Utilitas `cu`:** Untuk mode `run`, utilitas `cu` (call up) diperlukan untuk terhubung ke konsol `nmdm`. Pastikan sudah terinstal.

## 2. Cara Penggunaan

Skrip ini menerima satu argumen untuk menentukan mode operasi.

```bash
sudo sh simple-bhyve-vm-nmdm.sh [install|run]
```

### Mode Instalasi (`install`)
Gunakan mode ini untuk membuat disk virtual baru (jika belum ada) dan memulai proses instalasi FreeBSD dari file ISO. Konsol VM akan ditampilkan langsung di terminal Anda (`stdio`).

```bash
sudo sh simple-bhyve-vm-nmdm.sh install
```

**Langkah-langkah yang dilakukan:**
1.  Memeriksa keberadaan file ISO.
2.  Membuat file disk virtual (`my_freebsd_vm.img`) berukuran 20GB jika belum ada.
3.  Menghancurkan instans VM yang mungkin sedang berjalan dengan nama yang sama.
4.  Memuat installer dari ISO menggunakan `bhyveload` (konsol `stdio`).
5.  Menjalankan VM menggunakan `bhyve` dengan ISO sebagai CD-ROM dan disk virtual sebagai hard drive utama. Konsol VM akan ditampilkan langsung di terminal Anda (`stdio`).

### Mode Jalankan (`run`)
Gunakan mode ini untuk menjalankan VM FreeBSD yang sudah terinstal dari disk virtual yang ada. Konsol VM akan diakses melalui perangkat `nmdm` dan utilitas `cu`.

```bash
sudo sh simple-bhyve-vm-nmdm.sh run
```

**Langkah-langkah yang dilakukan:**
1.  Memeriksa keberadaan file disk virtual.
2.  Menghancurkan instans VM yang mungkin sedang berjalan dengan nama yang sama.
3.  Memastikan perangkat `nmdm` (`/dev/nmdm0A` dan `/dev/nmdm0B`) tersedia.
4.  Memuat bootloader dari disk virtual menggunakan `bhyveload` (konsol `stdio`).
5.  Menjalankan VM menggunakan `bhyve` di latar belakang, dengan konsol VM diarahkan ke `/dev/nmdm0A`.
6.  Meluncurkan `cu -l /dev/nmdm0B` untuk terhubung ke konsol VM. Anda akan berinteraksi dengan VM melalui jendela `cu` ini.
7.  Skrip akan menunggu hingga VM dimatikan.

## 3. Konfigurasi

Anda dapat menyesuaikan perilaku skrip dengan mengubah variabel-variabel berikut di bagian `--- KONFIGURASI VM ---`:

*   `VM_NAME`: Nama VM (default: `my_freebsd_vm`). Digunakan untuk identifikasi VM oleh bhyve dan sebagai bagian dari nama file disk.
*   `MEM_SIZE`: Ukuran memori yang dialokasikan untuk VM (default: `1G`). Contoh: `2G`, `2048M`.
*   `NUM_CPUS`: Jumlah CPU virtual yang dialokasikan untuk VM (default: `2`).
*   `TAP_DEV`: Nama perangkat TAP yang digunakan untuk jaringan VM (default: `tap0`).
*   `CONSOLE_NMDM_DEV`: Jalur dasar untuk perangkat konsol `nmdm` (default: `/dev/nmdm0`). Skrip akan menggunakan `/dev/nmdm0A` untuk `bhyve` dan `/dev/nmdm0B` untuk `cu`.
*   `DISK_IMG`: Jalur lengkap ke file disk virtual VM. Skrip akan membuat file ini jika tidak ada dalam mode `install`.
*   `ISO_PATH`: Jalur lengkap ke file ISO installer FreeBSD. **Pastikan untuk mengganti ini dengan jalur ISO Anda yang sebenarnya.**

## 4. Fungsi Bantuan

Skrip ini menggunakan beberapa fungsi bantuan internal:

*   `errmsg()`: Menampilkan pesan kesalahan ke `stderr` dan keluar dari skrip.
*   `check_root()`: Memeriksa apakah skrip dijalankan sebagai root. Jika tidak, akan menampilkan kesalahan.
*   `check_kld()`: Memeriksa apakah modul kernel tertentu (misalnya `vmm.ko` atau `nmdm.ko`) dimuat. Jika tidak, akan menampilkan kesalahan.
*   `destroy_vm()`: Mencoba menghancurkan instans VM yang sedang berjalan dengan `VM_NAME` yang ditentukan. Ini memastikan awal yang bersih untuk setiap operasi.
*   `create_disk_if_not_exists()`: Memeriksa apakah `DISK_IMG` ada. Jika tidak, ia akan membuat file kosong berukuran 20GB menggunakan `truncate`.
*   `ensure_nmdm_device_exists()`: Memeriksa keberadaan perangkat `nmdm` (`/dev/nmdmXA` dan `/dev/nmdmXB`) sebelum digunakan.

## 5. Fungsi Utama

*   `run_install_mode()`: Mengandung logika untuk menyiapkan dan menjalankan VM dalam mode instalasi menggunakan konsol `stdio`.
*   `run_vm_mode()`: Mengandung logika untuk menjalankan VM yang sudah terinstal menggunakan konsol `nmdm` dan `cu`.

## 6. Keluar dari Konsol VM

*   **Mode `install` (stdio):** Matikan sistem operasi tamu (VM) atau tekan `Ctrl+C` di terminal host tempat skrip dijalankan.
*   **Mode `run` (nmdm):** Setelah VM dimatikan dari dalam konsol, Anda mungkin perlu keluar dari sesi `cu` secara manual dengan menekan `Ctrl+a` lalu `c`.

## 7. Pemecahan Masalah

*   **`sudo: command not found` atau `Permission denied`**: Pastikan Anda menjalankan skrip dengan `sudo` di awal (`sudo sh simple-bhyve-vm-nmdm.sh ...`).
*   **`Syntax error: word unexpected`**: Pastikan tidak ada kesalahan ketik atau karakter yang tidak valid dalam skrip, terutama di sekitar `case` statement atau tanda kurung.
*   **`Modul kernel 'vmm.ko' tidak dimuat.`**: Jalankan `sudo kldload vmm`.
*   **`Modul kernel 'nmdm.ko' tidak dimuat.`**: Jalankan `sudo kldload nmdm`.
*   **`File ISO installer tidak ditemukan.`**: Periksa kembali jalur yang dikonfigurasi di variabel `ISO_PATH` dan pastikan file ISO ada di lokasi tersebut.
*   **`File disk VM tidak ditemukan.`**: Untuk mode `run`, pastikan Anda telah berhasil menginstal FreeBSD ke disk virtual sebelumnya menggunakan mode `install`.
*   **`Perangkat konsol nmdm (...) tidak ditemukan.`**: Pastikan modul `nmdm.ko` dimuat dan Anda memiliki izin yang sesuai. Terkadang, perangkat `nmdm` mungkin tidak dibuat secara otomatis atau memerlukan reboot setelah memuat modul.
*   **`Gagal meluncurkan cu.`**: Pastikan utilitas `cu` terinstal di sistem host Anda.
*   **Jaringan tidak berfungsi**: Pastikan perangkat TAP (`tap0`) telah dibuat (`sudo ifconfig tap0 create`) dan dikonfigurasi dengan benar (misalnya, ditambahkan ke bridge).
*   **VM tidak boot atau hang**: Periksa pesan kesalahan dari `bhyveload` atau `bhyve`. Pastikan konfigurasi VM (memori, CPU) sesuai dengan persyaratan OS tamu. Jika menu boot tidak muncul di mode `run`, pastikan `autoboot_delay` di `/boot/loader.conf` di dalam VM diatur ke nilai yang cukup besar (misalnya, 5 detik atau lebih) untuk memberi waktu `cu` terhubung.
