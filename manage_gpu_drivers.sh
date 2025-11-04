#!/bin/bash

# This script manages GPU drivers for passthrough.
# It can toggle between the default nouveau driver and the vfio driver.

# Usage: sudo ./manage_gpu_drivers.sh [on|off]
#   on:  Enable vfio for GPU passthrough (disables nouveau).
#   off: Disable vfio and re-enable nouveau.

set -e

# --- Configuration ---
NOUVEAU_BLACKLIST_FILE="/etc/modprobe.d/blacklist-nouveau.conf"
VFIO_MODULE_FILE="/etc/modules-load.d/vfio.conf"
VFIO_PCI_OPTIONS_FILE="/etc/modprobe.d/vfio.conf"

# --- Functions ---

# Function to enable vfio
enable_vfio() {
    echo "Enabling vfio for GPU passthrough..."

    # Blacklist nouveau
    echo "blacklist nouveau" > "$NOUVEAU_BLACKLIST_FILE"
    echo "options nouveau modeset=0" >> "$NOUVEAU_BLACKLIST_FILE"
    echo "Nouveau driver blacklisted."

    # Enable vfio modules
    echo "vfio" > "$VFIO_MODULE_FILE"
    echo "vfio_iommu_type1" >> "$VFIO_MODULE_FILE"
    echo "vfio_pci" >> "$VFIO_MODULE_FILE"
    echo "vfio_virqfd" >> "$VFIO_MODULE_FILE"
    echo "VFIO modules enabled."

    # Specify devices for vfio-pci
    echo "options vfio-pci ids=10de:2484,10de:228b" > "$VFIO_PCI_OPTIONS_FILE"
    echo "VFIO PCI options configured."

    # Update initramfs
    echo "Updating initramfs..."
    update-initramfs -u -k all

    echo "VFIO enabled. Please reboot your Proxmox host for the changes to take effect."
}

# Function to disable vfio
disable_vfio() {
    echo "Disabling vfio and re-enabling nouveau..."

    # Remove blacklist and module files
    rm -f "$NOUVEAU_BLACKLIST_FILE"
    rm -f "$VFIO_MODULE_FILE"
    rm -f "$VFIO_PCI_OPTIONS_FILE"
    echo "Removed nouveau blacklist and vfio module files."

    # Update initramfs
    echo "Updating initramfs..."
    update-initramfs -u -k all

    echo "VFIO disabled. Please reboot your Proxmox host for the changes to take effect."
}

# --- Main Script ---

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please use sudo." 
   exit 1
fi

# Parse command-line arguments
case "$1" in
    on)
        enable_vfio
        ;;
    off)
        disable_vfio
        ;;
    *)
        echo "Usage: sudo $0 [on|off]"
        exit 1
        ;;
esac
