/**
 * GPU Worker VMs with Dynamic GPU Passthrough
 * Uses hookscript to bind/unbind GPU on VM start/stop
 */

# =============================================================================
# UPLOAD HOOKSCRIPT TO PROXMOX
# =============================================================================

resource "proxmox_virtual_environment_file" "gpu_hookscript" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node
  
  source_raw {
    data = file("${path.module}/../scripts/gpu-hookscript.sh")
    file_name = "gpu-hookscript.pl"  # Must end in .pl for Proxmox
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# GPU WORKER VMs WITH HOOKSCRIPT
# =============================================================================

resource "proxmox_virtual_environment_vm" "gpu_workers_hookscript" {
  count = var.gpu_worker_count
  
  name        = "${var.cluster_name}-gpu-worker-${count.index + 1}"
  description = "K3s GPU worker with dynamic passthrough (hookscript)"
  node_name   = var.proxmox_node
  
  tags = concat(local.common_tags, ["worker", "gpu", "kata-enabled", "hookscript"])
  
  # Clone from template
  clone {
    vm_id = data.proxmox_virtual_environment_vm.template.vm_id
    full  = true
  }
  
  # CPU - Enable nested virtualization for Kata
  cpu {
    cores   = 8
    sockets = 1
    type    = "host"
  }
  
  # Memory
  memory {
    dedicated = 32768  # 32GB
  }
  
  # Disk
  disk {
    scsi {
      scsi0 {
        disk {
          size    = "50G"
          storage = var.proxmox_storage_pool
        }
      }
    }
  }

  # Network
  network {
    model  = "virtio"
    bridge = var.proxmox_bridge
  }

  # Cloud-init
  os_type = "cloud-init"
  ipconfig0 = "ip=dhcp"

  # Hookscript
  hookscript = proxmox_virtual_environment_file.gpu_hookscript.id

  # GPU Passthrough
  hostpci {
    "0" = {
      device = "02:00.0"
      pcie   = true
    }
    "1" = {
      device = "02:00.1"
      pcie   = true
    }
  }

  vga {
    type = "std"
  }
}