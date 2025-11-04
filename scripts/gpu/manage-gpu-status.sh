#!/bin/bash
#
# GPU Status Monitor
# Shows current GPU binding state and VM usage
#

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

GPU_PCI="${GPU_VIDEO_PCI:-0000:02:00.0}"

echo "=========================================="
echo " GPU Passthrough Status"
echo "=========================================="
echo ""

# Current driver
current_driver=$(basename $(readlink /sys/bus/pci/devices/$GPU_PCI/driver 2>/dev/null) 2>/dev/null || echo "none")

echo -n "GPU Status: "
case "$current_driver" in
    vfio-pci)
        echo -e "${YELLOW}PASSTHROUGH MODE${NC} (vfio-pci)"
        ;;
    nvidia)
        echo -e "${GREEN}HOST MODE${NC} (nvidia)"
        ;;
    nouveau)
        echo -e "${GREEN}HOST MODE${NC} (nouveau)"
        ;;
    none)
        echo -e "${RED}UNBOUND${NC}"
        ;;
    *)
        echo -e "${BLUE}$current_driver${NC}"
        ;;
esac

echo ""

# VMs using GPU
echo "VMs with GPU Passthrough:"
found=false
for vmid in $(qm list 2>/dev/null | awk 'NR>1 {print $1}'); do
    if qm config $vmid 2>/dev/null | grep -q "hostpci.*01:00"; then
        found=true
        status=$(qm status $vmid | awk '{print $2}')
        name=$(qm config $vmid | grep "^name:" | awk '{print $2}')
        echo "  VM $vmid ($name): $status"
    fi
done

if ! $found; then
    echo "  None configured"
fi

echo ""

# Lock status
echo -n "Lock Status: "
if [ -d "/var/lock/gpu-passthrough.lock" ]; then
    pid=$(cat /var/lock/gpu-passthrough.lock/pid 2>/dev/null)
    echo -e "${YELLOW}LOCKED${NC} (PID: $pid)"
else
    echo -e "${GREEN}Available${NC}"
fi

echo ""

# Recent log entries
if [ -f "/var/log/gpu-hookscript.log" ]; then
    echo "Recent Hookscript Activity:"
    tail -n 5 /var/log/gpu-hookscript.log | sed 's/^/  /'
fi
