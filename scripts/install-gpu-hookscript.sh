#!/bin/bash
#
# Install GPU Passthrough Hookscript on Proxmox
#
# This script:
# 1. Disables boot-time VFIO binding (removes your old config)
# 2. Installs the dynamic hookscript
# 3. Configures Proxmox to allow hookscripts
# 4. Tests the hookscript
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Check if on Proxmox
if ! command -v qm &> /dev/null; then
    log_error "This script must be run on a Proxmox host"
    exit 1
fi

log_info "================================================"
log_info "GPU Hookscript Installation"
log_info "================================================"
echo ""

# =============================================================================
# STEP 1: REMOVE BOOT-TIME VFIO CONFIGURATION
# =============================================================================

log_info "Step 1: Removing boot-time VFIO configuration..."

# Remove your old script's configuration
NOUVEAU_BLACKLIST_FILE="/etc/modprobe.d/blacklist-nouveau.conf"
VFIO_MODULE_FILE="/etc/modules-load.d/vfio.conf"
VFIO_PCI_OPTIONS_FILE="/etc/modprobe.d/vfio.conf"

if [ -f "$NOUVEAU_BLACKLIST_FILE" ]; then
    log_info "Removing $NOUVEAU_BLACKLIST_FILE"
    rm -f "$NOUVEAU_BLACKLIST_FILE"
fi

if [ -f "$VFIO_MODULE_FILE" ]; then
    log_info "Removing $VFIO_MODULE_FILE"
    rm -f "$VFIO_MODULE_FILE"
fi

if [ -f "$VFIO_PCI_OPTIONS_FILE" ]; then
    log_info "Removing $VFIO_PCI_OPTIONS_FILE"
    rm -f "$VFIO_PCI_OPTIONS_FILE"
fi

# Also remove from /etc/modules if present
if grep -q "vfio" /etc/modules 2>/dev/null; then
    log_info "Removing vfio entries from /etc/modules"
    sed -i '/vfio/d' /etc/modules
fi

# Remove GRUB parameters
log_info "Checking GRUB configuration..."
if grep -q "vfio-pci.ids" /etc/default/grub; then
    log_info "Removing vfio-pci.ids from GRUB"
    cp /etc/default/grub /etc/default/grub.bak.$(date +%s)
    sed -i 's/vfio-pci.ids=[^ ]*//g' /etc/default/grub
    update-grub
fi

log_success "Boot-time VFIO configuration removed"
echo ""

# =============================================================================
# STEP 2: DETECT GPU
# =============================================================================

log_info "Step 2: Detecting GPU..."

GPU_INFO=$(lspci -nn | grep -i nvidia | head -n 2)

if [ -z "$GPU_INFO" ]; then
    log_error "No NVIDIA GPU detected"
    log_info "Detected GPUs:"
    lspci | grep -i vga
    exit 1
fi

echo "$GPU_INFO"
echo ""

# Extract PCI addresses
GPU_VIDEO_PCI=$(echo "$GPU_INFO" | grep -i "VGA\|3D" | awk '{print $1}')
GPU_AUDIO_PCI=$(echo "$GPU_INFO" | grep -i "Audio" | awk '{print $1}')

# Extract PCI IDs
GPU_VIDEO_ID=$(echo "$GPU_INFO" | grep -i "VGA\|3D" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}' | head -n1)
GPU_AUDIO_ID=$(echo "$GPU_INFO" | grep -i "Audio" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}' | head -n1)

# Add 0000: prefix if not present
[[ "$GPU_VIDEO_PCI" != 0000:* ]] && GPU_VIDEO_PCI="0000:$GPU_VIDEO_PCI"
[[ "$GPU_AUDIO_PCI" != 0000:* ]] && GPU_AUDIO_PCI="0000:$GPU_AUDIO_PCI"

log_success "GPU detected:"
log_info "  Video: $GPU_VIDEO_PCI (ID: $GPU_VIDEO_ID)"
log_info "  Audio: $GPU_AUDIO_PCI (ID: $GPU_AUDIO_ID)"
echo ""

# =============================================================================
# STEP 3: CREATE HOOKSCRIPT
# =============================================================================

log_info "Step 3: Creating hookscript..."

HOOKSCRIPT_PATH="/var/lib/vz/snippets/gpu-hookscript.pl"

# Check if snippets directory exists
if [ ! -d "/var/lib/vz/snippets" ]; then
    log_info "Creating snippets directory..."
    mkdir -p /var/lib/vz/snippets
fi

# Create the hookscript with detected GPU values
cat > "$HOOKSCRIPT_PATH" << 'HOOKSCRIPT_EOF'
#!/bin/bash
# GPU Passthrough Hookscript - Auto-generated

set -e

# GPU Configuration (auto-detected)
GPU_VIDEO_PCI="GPU_VIDEO_PCI_PLACEHOLDER"
GPU_AUDIO_PCI="GPU_AUDIO_PCI_PLACEHOLDER"
GPU_VIDEO_ID="GPU_VIDEO_ID_PLACEHOLDER"
GPU_AUDIO_ID="GPU_AUDIO_ID_PLACEHOLDER"

# Paths
VFIO_DRIVER="/sys/bus/pci/drivers/vfio-pci"
NVIDIA_DRIVER="/sys/bus/pci/drivers/nvidia"
NOUVEAU_DRIVER="/sys/bus/pci/drivers/nouveau"
LOCK_FILE="/var/lock/gpu-passthrough.lock"
LOG_FILE="/var/log/gpu-hookscript.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

acquire_lock() {
    local timeout=30
    local count=0
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        [ $count -ge $timeout ] && return 1
        sleep 1
        ((count++))
    done
    echo $$ > "$LOCK_FILE/pid"
    return 0
}

release_lock() {
    [ -d "$LOCK_FILE" ] && rm -rf "$LOCK_FILE"
}

trap release_lock EXIT

get_current_driver() {
    local pci=$1
    if [ -e "/sys/bus/pci/devices/$pci/driver" ]; then
        basename "$(readlink "/sys/bus/pci/devices/$pci/driver")"
    else
        echo "none"
    fi
}

unbind_from_driver() {
    local pci=$1
    local current_driver=$(get_current_driver "$pci")
    if [ "$current_driver" != "none" ]; then
        log "Unbinding $pci from $current_driver"
        echo "$pci" > "/sys/bus/pci/drivers/$current_driver/unbind" 2>/dev/null || true
        sleep 1
    fi
}

bind_to_vfio() {
    local pci=$1
    local pci_id=$2
    
    log "Binding $pci to vfio-pci..."
    
    # Load module if needed
    lsmod | grep -q "^vfio_pci" || modprobe vfio-pci
    
    # Unbind current driver
    unbind_from_driver "$pci"
    
    # Add to vfio-pci
    echo "$pci_id" > "$VFIO_DRIVER/new_id" 2>/dev/null || true
    echo "$pci" > "$VFIO_DRIVER/bind" 2>/dev/null || {
        log_error "Failed to bind $pci to vfio-pci"
        return 1
    }
    
    log "Successfully bound $pci to vfio-pci"
    return 0
}

bind_to_host_driver() {
    local pci=$1
    local pci_id=$2
    
    log "Returning $pci to host..."
    
    # Unbind from vfio
    unbind_from_driver "$pci"
    echo "$pci_id" > "$VFIO_DRIVER/remove_id" 2>/dev/null || true
    
    # Try nouveau first
    if [ -d "$NOUVEAU_DRIVER" ]; then
        echo "$pci" > "$NOUVEAU_DRIVER/bind" 2>/dev/null && {
            log "Bound $pci to nouveau"
            return 0
        }
    fi
    
    # Try nvidia
    if [ -d "$NVIDIA_DRIVER" ]; then
        echo "$pci" > "$NVIDIA_DRIVER/bind" 2>/dev/null && {
            log "Bound $pci to nvidia"
            return 0
        }
    fi
    
    # Rescan
    echo 1 > "/sys/bus/pci/devices/$pci/remove"
    sleep 1
    echo 1 > /sys/bus/pci/rescan
    sleep 2
    
    log "Device $pci: $(get_current_driver "$pci")"
    return 0
}

is_gpu_in_use() {
    local count=0
    for vmid in $(qm list | awk 'NR>1 {print $1}'); do
        qm status $vmid | grep -q "running" || continue
        qm config $vmid | grep -q "hostpci.*01:00" && ((count++))
    done
    echo $count
}

pre_start() {
    log "=== VM $VMID pre-start: Binding GPU to VFIO ==="
    acquire_lock || exit 1
    
    # Stop display manager
    for dm in gdm lightdm sddm; do
        systemctl is-active --quiet $dm && systemctl stop $dm 2>/dev/null || true
    done
    sleep 2
    
    bind_to_vfio "$GPU_VIDEO_PCI" "$GPU_VIDEO_ID" || exit 1
    bind_to_vfio "$GPU_AUDIO_PCI" "$GPU_AUDIO_ID" || true
    
    log "GPU ready for passthrough"
    release_lock
}

post_stop() {
    log "=== VM $VMID post-stop: Returning GPU to host ==="
    acquire_lock || exit 1
    
    # Check if other VMs using GPU
    in_use=$(is_gpu_in_use)
    if [ $in_use -gt 0 ]; then
        log "GPU still in use by $in_use VM(s)"
        release_lock
        return 0
    fi
    
    bind_to_host_driver "$GPU_VIDEO_PCI" "$GPU_VIDEO_ID"
    bind_to_host_driver "$GPU_AUDIO_PCI" "$GPU_AUDIO_ID"
    
    # Restart display manager
    for dm in gdm lightdm sddm; do
        systemctl is-enabled --quiet $dm 2>/dev/null && systemctl start $dm && break
    done
    
    log "GPU returned to host"
    release_lock
}

# Main
VMID="$1"
PHASE="$2"

log "Hookscript: VMID=$VMID PHASE=$PHASE"

case "$PHASE" in
    pre-start) pre_start ;;
    post-stop) post_stop ;;
    *) log "Phase $PHASE - no action needed" ;;
esac

exit 0
HOOKSCRIPT_EOF

# Replace placeholders
sed -i "s|GPU_VIDEO_PCI_PLACEHOLDER|$GPU_VIDEO_PCI|g" "$HOOKSCRIPT_PATH"
sed -i "s|GPU_AUDIO_PCI_PLACEHOLDER|$GPU_AUDIO_PCI|g" "$HOOKSCRIPT_PATH"
sed -i "s|GPU_VIDEO_ID_PLACEHOLDER|$GPU_VIDEO_ID|g" "$HOOKSCRIPT_PATH"
sed -i "s|GPU_AUDIO_ID_PLACEHOLDER|$GPU_AUDIO_ID|g" "$HOOKSCRIPT_PATH"

# Make executable
chmod +x "$HOOKSCRIPT_PATH"

log_success "Hookscript created: $HOOKSCRIPT_PATH"
echo ""

# =============================================================================
# STEP 4: ENABLE HOOKSCRIPT SUPPORT
# =============================================================================

log_info "Step 4: Enabling hookscript support in Proxmox..."

# Add hookscript to allowed list
DATACENTER_CFG="/etc/pve/datacenter.cfg"

if ! grep -q "hookscript:" "$DATACENTER_CFG" 2>/dev/null; then
    log_info "Adding hookscript permission to datacenter config..."
    echo "hookscript: 1" >> "$DATACENTER_CFG"
fi

log_success "Hookscript support enabled"
echo ""

# =============================================================================
# STEP 5: UPDATE INITRAMFS
# =============================================================================

log_info "Step 5: Updating initramfs..."
update-initramfs -u -k all
log_success "Initramfs updated"
echo ""

# =============================================================================
# STEP 6: TEST HOOKSCRIPT
# =============================================================================

log_info "Step 6: Testing hookscript..."

# Test syntax
if bash -n "$HOOKSCRIPT_PATH"; then
    log_success "Hookscript syntax is valid"
else
    log_error "Hookscript has syntax errors"
    exit 1
fi

# Show current GPU state
log_info "Current GPU drivers:"
log_info "  Video: $(get_current_driver "$GPU_VIDEO_PCI")"
log_info "  Audio: $(get_current_driver "$GPU_AUDIO_PCI")"
echo ""

# =============================================================================
# FINAL INSTRUCTIONS
# =============================================================================

log_success "================================================"
log_success "Installation Complete!"
log_success "================================================"
echo ""
log_info "Next steps:"
echo ""
echo "1. REBOOT the Proxmox host (IMPORTANT!):"
echo "   reboot"
echo ""
echo "2. After reboot, attach hookscript to your VM:"
echo "   qm set <VMID> --hookscript local:snippets/gpu-hookscript.pl"
echo ""
echo "3. Configure GPU passthrough in VM:"
echo "   qm set <VMID> --hostpci0 $GPU_VIDEO_PCI,pcie=1"
echo "   qm set <VMID> --hostpci1 $GPU_AUDIO_PCI,pcie=1"
echo ""
echo "4. Start the VM:"
echo "   qm start <VMID>"
echo ""
echo "5. Monitor hookscript logs:"
echo "   tail -f /var/log/gpu-hookscript.log"
echo ""
log_warning "IMPORTANT: Reboot is required to fully disable boot-time VFIO binding!"
echo ""

# Save configuration for OpenTofu
CONFIG_OUTPUT="/tmp/gpu-config.env"
cat > "$CONFIG_OUTPUT" << EOF
# GPU Configuration for OpenTofu/Ansible
export GPU_VIDEO_PCI="$GPU_VIDEO_PCI"
export GPU_AUDIO_PCI="$GPU_AUDIO_PCI"
export GPU_VIDEO_ID="$GPU_VIDEO_ID"
export GPU_AUDIO_ID="$GPU_AUDIO_ID"
export HOOKSCRIPT_PATH="local:snippets/gpu-hookscript.pl"
EOF

log_info "GPU configuration saved to: $CONFIG_OUTPUT"
log_info "Source this file before running OpenTofu:"
log_info "  source $CONFIG_OUTPUT"
