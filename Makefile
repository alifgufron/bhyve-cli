SHELL = /bin/sh

# Makefile for bhyve-cli

# --- Configuration ---
PREFIX ?= /usr/local
BIN_DIR = $(PREFIX)/sbin
ETC_DIR = $(PREFIX)/etc
SHARE_DIR = $(PREFIX)/share
RC_DIR = $(ETC_DIR)/rc.d

APP_NAME = bhyve-cli
SHARE_SUBDIR = $(SHARE_DIR)/$(APP_NAME)
ETC_APP_DIR = $(ETC_DIR)/$(APP_NAME)
VM_CONFIG_DIR = $(ETC_APP_DIR)/vm.d

# --- Source Files ---
SRC_DIR = src
MAIN_SCRIPT = $(SRC_DIR)/$(APP_NAME)
LIB_DIR = $(SRC_DIR)/lib
RC_SCRIPT = rc.d/$(APP_NAME)
FIRMWARE_DIR = firmware

# --- Installation Targets ---
.PHONY: all install uninstall clean

all:
	@echo "Usage: make [install|uninstall|clean]"

install:
	@echo "Installing $(APP_NAME)..."
	@/bin/sh -c 'echo "PATH: $$PATH"; echo "ID_U: $$(id -u)"; echo "WHOAMI: $$(whoami)"' || true
	@if [ "$$(id -u)" != "0" ]; then \
		echo "ERROR: Installation requires root privileges." >&2; \
		exit 1; \
	fi

	@mkdir -p $(DESTDIR)$(SHARE_SUBDIR)/lib
	@mkdir -p $(DESTDIR)$(SHARE_SUBDIR)/firmware
	@mkdir -p $(DESTDIR)$(ETC_APP_DIR)
	@mkdir -p $(DESTDIR)$(VM_CONFIG_DIR)
	@mkdir -p $(DESTDIR)$(RC_DIR)

	@cp $(MAIN_SCRIPT) $(DESTDIR)$(BIN_DIR)/$(APP_NAME)
	@chmod +x $(DESTDIR)$(BIN_DIR)/$(APP_NAME)

	@cp -R $(LIB_DIR)/* $(DESTDIR)$(SHARE_SUBDIR)/lib/
	@chmod +x $(DESTDIR)$(SHARE_SUBDIR)/lib/functions/network_cleanup_all.sh
	@cp -R $(FIRMWARE_DIR)/* $(DESTDIR)$(SHARE_SUBDIR)/firmware/

	@cp $(RC_SCRIPT) $(DESTDIR)$(RC_DIR)/

	@echo "Installation complete."
	@echo "--------------------------------------------------"
	@echo "To enable the service, add the following to /etc/rc.conf:"
	@echo 'bhyve_cli_enable="YES"'
	@echo "Then, you can start the service with:"
	@echo "service bhyve-cli start"
	@echo "--------------------------------------------------"

uninstall:
	@echo "Uninstalling $(APP_NAME)..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "ERROR: Uninstallation requires root privileges." >&2; \
		exit 1; \
	fi
	@echo "Running network cleanup script..."
	@$(SRC_DIR)/lib/functions/network_cleanup_all.sh || echo "WARNING: Network cleanup script failed or encountered issues."
	@rm -f $(DESTDIR)$(BIN_DIR)/$(APP_NAME)
	@rm -rf $(DESTDIR)$(SHARE_SUBDIR)
	@rm -rf $(DESTDIR)$(ETC_APP_DIR)
	@rm -f $(DESTDIR)$(RC_DIR)/$(APP_NAME)

	@echo "Uninstallation complete."
	@echo "--------------------------------------------------"
	@echo "NOTE: User data (VMs, disks, ISOs) is NOT deleted."
	@echo "If you wish to remove them, delete them manually from:"
	@echo "  - VMs & Disks: /var/bhyve/vm.d"
	@echo "  - ISOs: /var/bhyve/iso"
	@echo "  - Templates: /var/bhyve/vm.d/templates"
	@echo "(These are default paths and may be different if you configured them manually.)"
	@echo "--------------------------------------------------"

clean:
	@echo "Cleaning up..."
	# Add cleanup tasks here if needed, e.g., removing generated files
	@echo "Cleanup complete."
