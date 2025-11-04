# Dynamic GPU Passthrough with Hookscripts

## Overview

This system allows **dynamic GPU binding** - the GPU stays with the Proxmox host for console/display until a VM needs it, then automatically switches to passthrough mode.

### ✅ **Benefits vs Boot-Time Binding**

| Feature | Boot-Time VFIO | Hookscript (Dynamic) |
|---------|----------------|---------------------|
| **Host Console Access** | ❌ Lost at boot | ✅ Available until VM starts |
| **Multiple VM Support** | ✅ Yes | ✅ Yes (with ref counting) |
| **Proxmox Web UI** | ❌ Limited (no GPU) | ✅ Full access |
| **Recovery** | ⚠️ Requires reboot | ✅ Automatic on VM stop |
| **Flexibility** | ❌ Fixed at boot | ✅ On-demand |

## 🚀 **Quick Start**

### **Prerequisites**

- Proxmox VE 7.x or 8.x
- NVIDIA GPU (AMD GPUs need minor modifications)
- IOMMU enabled in BIOS
- Root/sudo access to Proxmox host

### **Step 1: Enable IOMMU (One-Time Setup)**

```bash
# SSH to Proxmox host
ssh root@proxmox

# Edit GRUB
nano /etc/default/grub

# For Intel CPUs:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"

# For AMD CPUs:
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"

# Update GRUB and reboot
update-grub
reboot
```

### **Step 2: Install Hookscript**

```bash
# Download installation script
cd /root
wget https://your-repo/scripts/install-gpu-hookscript.sh
chmod +x install-gpu-hookscript.sh

# Run installer (will auto-detect GPU)
./install-gpu-hookscript.sh

# REBOOT (required to disable old VFIO config)
reboot
```

### **Step 3: Configure VM for GPU Passthrough**

```bash
# After reboot, attach hookscript to VM
VMID=100
qm set $VMID --hookscript local:snippets/gpu-hookscript.pl

# Add GPU passthrough
qm set $VMID --hostpci0 01:00.0,pcie=1  # Video
qm set $VMID --hostpci1 01:00.1,pcie=1  # Audio

# Set VGA to std (not none, so you have console access)
qm set $VMID --vga std

# Start VM
qm start $VMID

# Watch the magic happen
tail -f /var/log/gpu-hookscript.log
```

## 📋 **How It Works**

### **VM Start Sequence**

```
User starts VM
    ↓
Proxmox calls: gpu-hookscript.pl <VMID> pre-start
    ↓
Hookscript acquires lock
    ↓
Stops display manager (gdm/lightdm)
    ↓
Unbinds GPU from nouveau/nvidia driver
    ↓
Binds GPU to vfio-pci driver
    ↓
Releases lock
    ↓
VM boots with GPU access
```

### **VM Stop Sequence**

```
User stops VM
    ↓
Proxmox calls: gpu-hookscript.pl <VMID> post-stop
    ↓
Hookscript acquires lock
    ↓
Checks if other VMs using GPU (reference counting)
    ↓
If no other VMs: Unbind from vfio-pci
    ↓
Bind back to nouveau/nvidia driver
    ↓
Restart display manager
    ↓
Releases lock
    ↓
GPU available to host again
```

## 🔧 **OpenTofu Integration**

### **Update your `terraform/variables.tf`**

```hcl
variable "gpu_pci_devices" {
  description = "GPU PCI addresses for passthrough"
  type = list(object({
    host_pci = string
    pcie     = bool
  }))
  default = [
    {
      host_pci = "01:00.0"  # Video - UPDATE THIS
      pcie     = true
    },
    {
      host_pci = "01:00.1"  # Audio - UPDATE THIS
      pcie     = true
    }
  ]
}

variable "use_gpu_hookscript" {
  description = "Use dynamic GPU binding (recommended)"
  type        = bool
  default     = true
}
```

### **Deploy with OpenTofu**

```bash
# Source GPU configuration
source /tmp/gpu-config.env

# Initialize OpenTofu
cd terraform
tofu init

# Plan deployment
tofu plan \
  -var="gpu_pci_devices=[{host_pci=\"$GPU_VIDEO_PCI\",pcie=true},{host_pci=\"$GPU_AUDIO_PCI\",pcie=true}]" \
  -var="use_gpu_hookscript=true"

# Apply
tofu apply
```

## 🐛 **Troubleshooting**

### **Issue: Hookscript not executing**

**Symptoms:**
- VM starts but GPU not bound
- No entries in `/var/log/gpu-hookscript.log`

**Solutions:**

```bash
# 1. Check if hookscript is attached
qm config <VMID> | grep hookscript

# 2. Verify hookscript exists
ls -l /var/lib/vz/snippets/gpu-hookscript.pl

# 3. Test hookscript manually
/var/lib/vz/snippets/gpu-hookscript.pl <VMID> pre-start
/var/lib/vz/snippets/gpu-hookscript.pl <VMID> post-stop

# 4. Check Proxmox config allows hookscripts
cat /etc/pve/datacenter.cfg | grep hookscript
# Should show: hookscript: 1

# 5. Check permissions
chmod +x /var/lib/vz/snippets/gpu-hookscript.pl
```

### **Issue: GPU still bound to vfio-pci at boot**

**Symptoms:**
- No Proxmox console after reboot
- `lspci -k` shows vfio-pci at boot

**Solutions:**

```bash
# 1. Check for lingering VFIO configs
grep -r "vfio" /etc/modprobe.d/
grep -r "vfio" /etc/modules-load.d/
grep "vfio" /etc/modules

# 2. Remove any found files
rm /etc/modprobe.d/vfio.conf
rm /etc/modprobe.d/blacklist-nouveau.conf
rm /etc/modules-load.d/vfio.conf

# 3. Check GRUB
grep vfio /etc/default/grub
# Should NOT contain vfio-pci.ids=

# 4. If GRUB has vfio-pci.ids, remove it
nano /etc/default/grub
# Remove vfio-pci.ids=10de:xxxx,10de:yyyy
update-grub

# 5. Rebuild initramfs
update-initramfs -u -k all

# 6. Reboot
reboot
```

### **Issue: Lock timeout**

**Symptoms:**
```
ERROR: Failed to acquire lock after 30s
```

**Solutions:**

```bash
# Check for stale lock
ls -l /var/lock/gpu-passthrough.lock

# Remove stale lock (if no VM is actually starting)
rm -rf /var/lock/gpu-passthrough.lock

# Check if multiple VMs starting simultaneously
qm list | grep running
```

### **Issue: GPU not returning to host after VM stop**

**Symptoms:**
- VM stops but Proxmox console still black
- `lspci -k` shows `Kernel driver in use: vfio-pci`

**Solutions:**

```bash
# 1. Check hookscript logs
tail -50 /var/log/gpu-hookscript.log

# 2. Manually unbind and rebind
GPU_PCI="0000:01:00.0"  # Your GPU address

# Unbind from vfio-pci
echo "$GPU_PCI" > /sys/bus/pci/drivers/vfio-pci/unbind

# Bind to nouveau
echo "$GPU_PCI" > /sys/bus/pci/drivers/nouveau/bind

# Restart display manager
systemctl restart gdm  # or lightdm/sddm

# 3. Check if other VMs using GPU
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  qm status $vmid | grep -q running && qm config $vmid | grep -q hostpci && echo "VM $vmid using GPU"
done
```

## 📊 **Monitoring**

### **Real-Time Log Monitoring**

```bash
# Watch hookscript activity
tail -f /var/log/gpu-hookscript.log

# Colored output with grep
tail -f /var/log/gpu-hookscript.log | grep --color=auto -E 'ERROR|pre-start|post-stop|Binding|Successfully'
```

### **Check GPU Status**

```bash
#!/bin/bash
# gpu-status.sh - Quick GPU status checker

GPU_PCI="0000:01:00.0"  # Change to your GPU

echo "=== GPU Status ==="
echo "Current driver: $(basename $(readlink /sys/bus/pci/devices/$GPU_PCI/driver 2>/dev/null) 2>/dev/null || echo 'none')"
echo ""

echo "=== VMs with GPU Passthrough ==="
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  if qm config $vmid 2>/dev/null | grep -q "hostpci.*01:00"; then
    status=$(qm status $vmid | awk '{print $2}')
    echo "VM $vmid: $status"
  fi
done
echo ""

echo "=== Lock Status ==="
if [ -d "/var/lock/gpu-passthrough.lock" ]; then
  pid=$(cat /var/lock/gpu-passthrough.lock/pid 2>/dev/null)
  echo "Locked by PID: $pid"
else
  echo "Not locked"
fi
```

### **Prometheus Metrics (Advanced)**

```bash
# Export GPU binding metrics for Prometheus
cat > /usr/local/bin/gpu-metrics-exporter.sh << 'EOF'
#!/bin/bash
GPU_PCI="0000:01:00.0"
METRICS_FILE="/var/lib/node_exporter/textfile_collector/gpu_binding.prom"

mkdir -p /var/lib/node_exporter/textfile_collector

driver=$(basename $(readlink /sys/bus/pci/devices/$GPU_PCI/driver 2>/dev/null) 2>/dev/null || echo "none")

cat > "$METRICS_FILE" << METRICS
# HELP gpu_vfio_bound Whether GPU is bound to vfio-pci (1) or host driver (0)
# TYPE gpu_vfio_bound gauge
gpu_vfio_bound{driver="$driver"} $( [ "$driver" = "vfio-pci" ] && echo 1 || echo 0 )
METRICS
EOF

chmod +x /usr/local/bin/gpu-metrics-exporter.sh

# Add to cron
echo "* * * * * /usr/local/bin/gpu-metrics-exporter.sh" | crontab -
```

## 🔐 **Security Considerations**

### **Lock File Security**

The hookscript uses a lock file to prevent race conditions. Ensure:

```bash
# Lock directory has proper permissions
ls -ld /var/lock
# Should be: drwxrwxrwt (sticky bit set)

# If not:
chmod 1777 /var/lock
```

### **Hookscript Permissions**

```bash
# Hookscript should be executable only by root
chown root:root /var/lib/vz/snippets/gpu-hookscript.pl
chmod 700 /var/lib/vz/snippets/gpu-hookscript.pl
```

### **Audit Logging**

```bash
# Enable audit logging for GPU binding events
apt-get install auditd

# Add audit rules
cat >> /etc/audit/rules.d/gpu.rules << 'EOF'
-w /sys/bus/pci/drivers/vfio-pci/bind -p wa -k gpu_vfio_bind
-w /sys/bus/pci/drivers/vfio-pci/unbind -p wa -k gpu_vfio_unbind
-w /sys/bus/pci/drivers/nouveau/bind -p wa -k gpu_nouveau_bind
EOF

service auditd restart

# View GPU binding events
ausearch -k gpu_vfio_bind
```

## 📚 **Advanced Configuration**

### **Multi-GPU Support**

If you have multiple GPUs, create separate hookscripts:

```bash
# GPU 1 (01:00.x)
cp /var/lib/vz/snippets/gpu-hookscript.pl /var/lib/vz/snippets/gpu1-hookscript.pl
# Edit GPU1 hookscript to use GPU1 PCI addresses

# GPU 2 (02:00.x)
cp /var/lib/vz/snippets/gpu-hookscript.pl /var/lib/vz/snippets/gpu2-hookscript.pl
# Edit GPU2 hookscript to use GPU2 PCI addresses

# Attach to different VMs
qm set 100 --hookscript local:snippets/gpu1-hookscript.pl
qm set 101 --hookscript local:snippets/gpu2-hookscript.pl
```

### **Custom Driver Binding**

To prefer specific drivers, edit the hookscript:

```bash
nano /var/lib/vz/snippets/gpu-hookscript.pl

# Find bind_to_host_driver function and reorder:
bind_to_host_driver() {
    # Try nvidia proprietary FIRST
    if [ -d "$NVIDIA_DRIVER" ]; then
        echo "$pci" > "$NVIDIA_DRIVER/bind" 2>/dev/null && {
            log "Bound $pci to nvidia"
            return 0
        }
    fi
    
    # Then try nouveau
    if [ -d "$NOUVEAU_DRIVER" ]; then
        # ...
    fi
}
```

### **Integration with Kubernetes Operator**

For the RBaaS system, add VM lifecycle management:

```python
# In your RBaaS Operator
async def create_browser_session(self, session: BrowserSession):
    # Start Proxmox VM with GPU
    vmid = self.get_available_gpu_vm()
    
    # VM start triggers hookscript automatically
    await self.proxmox_api.start_vm(vmid)
    
    # Wait for GPU to bind
    await self.wait_for_gpu_ready(vmid)
    
    # Deploy Kata container with GPU passthrough
    pod = self.create_kata_gpu_pod(session)
    await self.k8s_api.create_namespaced_pod(pod)
```

## 🎯 **Best Practices**

1. **Always reboot after changes** to VFIO/IOMMU configuration
2. **Test hookscript manually** before attaching to production VMs
3. **Monitor logs** during first few VM starts/stops
4. **Keep backups** of working hookscript configurations
5. **Document PCI addresses** for your hardware
6. **Use lock files** to prevent concurrent GPU access
7. **Set up monitoring** for production deployments

## 📖 **References**

- [Proxmox PCI Passthrough](https://pve.proxmox.com/wiki/PCI_Passthrough)
- [Proxmox Hookscripts](https://pve.proxmox.com/wiki/Hookscripts)
- [VFIO - Linux KVM](https://www.kernel.org/doc/Documentation/vfio.txt)
- [Kata Containers GPU Support](https://github.com/kata-containers/kata-containers/blob/main/docs/design/gpu-passthrough.md)

---

**Version:** 1.0  
**Last Updated:** 2025-11-03  
**Maintainer:** DevOps Team
