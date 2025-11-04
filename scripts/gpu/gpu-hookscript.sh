#!/bin/bash
#
# Proxmox GPU Passthrough Hookscript
# 
# This script dynamically binds/unbinds GPU to/from VFIO-PCI driver
# when a VM with GPU passthrough starts or stops.
#
# Installation:
#   1. Copy to: /var/lib/vz/snippets/gpu-hookscript.pl (yes, .pl extension)
#   2. Make executable: chmod +x /var/lib/vz/snippets/gpu-hookscript.pl
#   3. Attach to VM: qm set <VMID> --hookscript local:snippets/gpu-hookscript.pl
#
# The .pl extension is required by Proxmox, but this is actually a bash script.
#

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================

# GPU PCI addresses (find with: lspci | grep -i nvidia)
GPU_VIDEO_PCI="0000:02:00.0"     # Main GPU device
GPU_AUDIO_PCI="0000:02:00.1"     # GPU Audio device

# GPU PCI IDs (find with: lspci -n -s 01:00)
GPU_VIDEO_ID="10de:2484"          # NVIDIA vendor:device ID
GPU_AUDIO_ID="10de:228b"          # NVIDIA audio vendor:device ID

# Driver paths
VFIO_DRIVER="/sys/bus/pci/drivers/vfio-pci"
NVIDIA_DRIVER="/sys/bus/pci/drivers/nvidia"
NOUVEAU_DRIVER="/sys/bus/pci/drivers/nouveau"

# Lock file to prevent race conditions
LOCK_FILE="/var/lock/gpu-passthrough.lock"

# Logging
LOG_FILE="/var/log/gpu-hookscript.log"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# =============================================================================
# LOCKING MECHANISM
# =============================================================================

acquire_lock() {
    local timeout=30
    local count=0
    
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        if [ $count -ge $timeout ]; then
            log_error "Failed to acquire lock after ${timeout}s"
            return 1
        fi
        sleep 1
        ((count++))
    done
    
    # Store our PID in lock
    echo $$ > "$LOCK_FILE/pid"
    log "Lock acquired by PID $$"
    return 0
}

release_lock() {
    if [ -d "$LOCK_FILE" ]; then
        rm -rf "$LOCK_FILE"
        log "Lock released by PID $$"
    }
}

# Ensure lock is released on exit
trap release_lock EXIT

# =============================================================================
# GPU DETECTION FUNCTIONS
# =============================================================================

get_current_driver() {
    local pci=$1
    
    if [ -e "/sys/bus/pci/devices/$pci/driver" ]; then
        basename "$(readlink "/sys/bus/pci/devices/$pci/driver")"
    else
        echo "none"
    fi
}

is_gpu_in_use() {
    # Check if any VM is using the GPU
    local count=0
    
    for vmid in $(qm list | awk 'NR>1 {print $1}'); do
        if qm status $vmid | grep -q "running"; then
            if qm config $vmid | grep -q "hostpci.*01:00"; then
                ((count++))
            fi
        fi
    done
    
    echo $count
}

# =============================================================================
# GPU BINDING FUNCTIONS
# =============================================================================

unbind_from_driver() {
    local pci=$1
    local current_driver=$(get_current_driver "$pci")
    
    if [ "$current_driver" != "none" ]; then
        log "Unbinding $pci from driver: $current_driver"
        echo "$pci" > "/sys/bus/pci/drivers/$current_driver/unbind" 2>/dev/null || {
            log_error "Failed to unbind $pci from $current_driver"
            return 1
        }
        sleep 1
    else
        log "$pci is not bound to any driver"
    }
    
    return 0
}

bind_to_vfio() {
    local pci=$1
    local pci_id=$2
    
    log "Binding $pci to vfio-pci driver..."
    
    # Make sure vfio-pci module is loaded
    if ! lsmod | grep -q "^vfio_pci"; then
        log "Loading vfio-pci module..."
        modprobe vfio-pci
    fi
    
    # Remove device ID from current driver (if any)
    current_driver=$(get_current_driver "$pci")
    if [ "$current_driver" != "none" ] && [ "$current_driver" != "vfio-pci" ]; then
        unbind_from_driver "$pci" || return 1
    fi
    
    # Add PCI ID to vfio-pci driver (if not already added)
    if ! grep -q "$pci_id" "$VFIO_DRIVER/new_id" 2>/dev/null; then
        echo "$pci_id" > "$VFIO_DRIVER/new_id" 2>/dev/null || {
            log "PCI ID $pci_id already registered with vfio-pci"
        }
    fi
    
    # Bind to vfio-pci
    if [ ! -e "/sys/bus/pci/devices/$pci/driver" ] || [ "$(get_current_driver "$pci")" != "vfio-pci" ]; then
        echo "$pci" > "$VFIO_DRIVER/bind" 2>/dev/null || {
            log_error "Failed to bind $pci to vfio-pci"
            return 1
        }
    fi
    
    # Verify
    local new_driver=$(get_current_driver "$pci")
    if [ "$new_driver" = "vfio-pci" ]; then
        log "Successfully bound $pci to vfio-pci"
        return 0
    else
        log_error "Binding failed. Current driver: $new_driver"
        return 1
    fi
}

bind_to_host_driver() {
    local pci=$1
    local pci_id=$2
    
    log "Binding $pci back to host driver..."
    
    # Unbind from vfio-pci
    if [ "$(get_current_driver "$pci")" = "vfio-pci" ]; then
        unbind_from_driver "$pci" || return 1
    fi
    
    # Remove PCI ID from vfio-pci
    echo "$pci_id" > "$VFIO_DRIVER/remove_id" 2>/dev/null || true
    
    # Try to bind to nouveau first (open-source, safe)
    if [ -d "$NOUVEAU_DRIVER" ]; then
        log "Attempting to bind to nouveau driver..."
        echo "$pci" > "$NOUVEAU_DRIVER/bind" 2>/dev/null && {
            log "Successfully bound $pci to nouveau"
            return 0
        }
    fi
    
    # If nouveau fails, try nvidia proprietary driver
    if [ -d "$NVIDIA_DRIVER" ]; then
        log "Attempting to bind to nvidia driver..."
        echo "$pci" > "$NVIDIA_DRIVER/bind" 2>/dev/null && {
            log "Successfully bound $pci to nvidia"
            return 0
        }
    fi
    
    # Let kernel auto-bind
    log "Triggering kernel auto-bind for $pci..."
    echo 1 > "/sys/bus/pci/devices/$pci/remove"
    sleep 1
    echo 1 > /sys/bus/pci/rescan
    sleep 2
    
    local new_driver=$(get_current_driver "$pci")
    log "Device $pci now using: $new_driver"
    
    return 0
}

# =============================================================================
# MAIN HOOK HANDLERS
# =============================================================================

pre_start() {
    log "================================================"
    log "VM $VMID pre-start: Preparing GPU for passthrough"
    log "================================================"
    
    acquire_lock || exit 1
    
    # Check current GPU state
    log "Current GPU drivers:"
    log "  Video ($GPU_VIDEO_PCI): $(get_current_driver "$GPU_VIDEO_PCI")"
    log "  Audio ($GPU_AUDIO_PCI): $(get_current_driver "$GPU_AUDIO_PCI")"
    
    # Check if GPU is already in use
    in_use=$(is_gpu_in_use)
    if [ $in_use -gt 0 ]; then
        log "GPU is already in use by $in_use VM(s)"
    fi
    
    # Bind GPU to VFIO
    log "Binding GPU to VFIO driver..."
    
    # Stop display manager if running (to release GPU)
    if systemctl is-active --quiet gdm || systemctl is-active --quiet lightdm || systemctl is-active --quiet sddm; then
        log "Stopping display manager..."
        systemctl stop gdm lightdm sddm 2>/dev/null || true
        sleep 2
    fi
    
    # Bind video device
    if ! bind_to_vfio "$GPU_VIDEO_PCI" "$GPU_VIDEO_ID"; then
        log_error "Failed to bind video device to VFIO"
        release_lock
        exit 1
    fi
    
    # Bind audio device
    if ! bind_to_vfio "$GPU_AUDIO_PCI" "$GPU_AUDIO_ID"; then
        log_error "Failed to bind audio device to VFIO"
        # Don't fail completely, audio passthrough is optional
    fi
    
    log "GPU successfully prepared for passthrough"
    release_lock
}

post_start() {
    log "VM $VMID post-start: GPU passthrough active"
    # Nothing to do here, GPU is already bound
}

pre_stop() {
    log "VM $VMID pre-stop: GPU still in use"
    # Nothing to do here, keep GPU in VFIO until VM stops
}

post_stop() {
    log "================================================"
    log "VM $VMID post-stop: Returning GPU to host"
    log "================================================"
    
    acquire_lock || exit 1
    
    # Check if other VMs are still using GPU
    in_use=$(is_gpu_in_use)
    if [ $in_use -gt 0 ]; then
        log "GPU is still in use by $in_use other VM(s), leaving in VFIO mode"
        release_lock
        return 0
    fi
    
    log "No other VMs using GPU, returning to host..."
    
    # Bind back to host driver
    if ! bind_to_host_driver "$GPU_VIDEO_PCI" "$GPU_VIDEO_ID"; then
        log_error "Failed to bind video device back to host driver"
    fi
    
    if ! bind_to_host_driver "$GPU_AUDIO_PCI" "$GPU_AUDIO_ID"; then
        log_error "Failed to bind audio device back to host driver"
    fi
    
    # Restart display manager if needed
    if systemctl is-enabled --quiet gdm 2>/dev/null; then
        log "Restarting display manager..."
        systemctl start gdm
    elif systemctl is-enabled --quiet lightdm 2>/dev/null; then
        systemctl start lightdm
    elif systemctl is-enabled --quiet sddm 2>/dev/null; then
        systemctl start sddm
    fi
    
    log "GPU returned to host"
    release_lock
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

# Proxmox passes: <VMID> <phase> [<extra>]
VMID="$1"
PHASE="$2"

log "Hookscript called: VMID=$VMID PHASE=$PHASE"

case "$PHASE" in
    pre-start)
        pre_start
        ;;
    post-start)
        post_start
        ;;
    pre-stop)
        pre_stop
        ;;
    post-stop)
        post_stop
        ;;
    *)
        log "Unknown phase: $PHASE"
        exit 0
        ;;
esac

log "Hookscript completed successfully"
exit 0
