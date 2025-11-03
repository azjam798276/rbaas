/**
 * Nexus Sandbox Framework - OpenTofu Infrastructure as Code
 * 
 * This configuration provisions:
 * - K3s control plane VMs (HA)
 * - Standard worker VMs
 * - GPU-enabled worker VMs with passthrough
 * - All configured for nested virtualization (Kata Containers)
 */

# =============================================================================
# TERRAFORM/OPENTOFU CONFIGURATION
# =============================================================================

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50.0"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  
  # Uncomment for remote state (recommended for production)
  # backend "s3" {
  #   bucket = "nexus-terraform-state"
  #   key    = "nexus-sandbox/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# =============================================================================
# VARIABLES
# =============================================================================

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "cluster_name" {
  description = "Name prefix for cluster VMs"
  type        = string
  default     = "nexus-k3s"
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
  
  validation {
    condition     = var.control_plane_count >= 1 && var.control_plane_count % 2 == 1
    error_message = "Control plane count must be odd (1, 3, 5, etc.) for etcd quorum"
  }
}

variable "worker_count" {
  description = "Number of standard worker nodes"
  type        = number
  default     = 3
}

variable "gpu_worker_count" {
  description = "Number of GPU-enabled worker nodes"
  type        = number
  default     = 2
}

variable "template_name" {
  description = "Name of the cloud-init template"
  type        = string
  default     = "ubuntu-2204-cloudinit-template"
}

variable "network_cidr" {
  description = "CIDR block for cluster network"
  type        = string
  default     = "192.168.100.0/24"
}

variable "network_gateway" {
  description = "Network gateway"
  type        = string
  default     = "192.168.100.1"
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-zfs"
}

variable "gpu_pci_devices" {
  description = "PCI addresses of GPUs to pass through"
  type = list(object({
    host_pci = string
    pcie     = bool
  }))
  default = [
    {
      host_pci = "01:00.0"
      pcie     = true
    },
    {
      host_pci = "01:00.1"
      pcie     = true
    }
  ]
}

# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  
  # Accept self-signed certificates (set to false in production)
  insecure = true
  
  ssh {
    agent = true
  }
}

# =============================================================================
# LOCAL VARIABLES
# =============================================================================

locals {
  # Calculate IP addresses
  control_plane_ips = [
    for i in range(var.control_plane_count) :
    cidrhost(var.network_cidr, 10 + i)
  ]
  
  worker_ips = [
    for i in range(var.worker_count) :
    cidrhost(var.network_cidr, 20 + i)
  ]
  
  gpu_worker_ips = [
    for i in range(var.gpu_worker_count) :
    cidrhost(var.network_cidr, 30 + i)
  ]
  
  # Common cloud-init configuration
  common_cloud_init = {
    user  = "ubuntu"
    ssh_authorized_keys = [var.ssh_public_key]
    
    package_update = true
    package_upgrade = true
    
    packages = [
      "curl",
      "wget",
      "git",
      "htop",
      "iotop",
      "net-tools",
      "qemu-guest-agent"
    ]
    
    runcmd = [
      # Enable and start QEMU guest agent
      "systemctl enable qemu-guest-agent",
      "systemctl start qemu-guest-agent",
      
      # Configure kernel parameters for Kubernetes
      "echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.d/99-kubernetes.conf",
      "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/99-kubernetes.conf",
      "echo 'net.bridge.bridge-nf-call-ip6tables = 1' >> /etc/sysctl.d/99-kubernetes.conf",
      "sysctl --system",
      
      # Load required kernel modules
      "modprobe overlay",
      "modprobe br_netfilter",
      "echo 'overlay' >> /etc/modules-load.d/containerd.conf",
      "echo 'br_netfilter' >> /etc/modules-load.d/containerd.conf",
      
      # Disable swap (required for Kubernetes)
      "swapoff -a",
      "sed -i '/ swap / s/^/#/' /etc/fstab"
    ]
  }
  
  # Tags for all VMs
  common_tags = [
    "nexus-sandbox",
    "kubernetes",
    "managed-by-terraform"
  ]
}

# =============================================================================
# CONTROL PLANE NODES
# =============================================================================

resource "proxmox_virtual_environment_vm" "control_plane" {
  count = var.control_plane_count
  
  name        = "${var.cluster_name}-control-${count.index + 1}"
  description = "K3s control plane node ${count.index + 1}"
  node_name   = var.proxmox_node
  
  tags = concat(local.common_tags, ["control-plane", "etcd"])
  
  # Clone from cloud-init template
  clone {
    vm_id = data.proxmox_virtual_environment_vm.template.vm_id
    full  = true
  }
  
  # CPU configuration - CRITICAL for nested virtualization
  cpu {
    cores = 4
    sockets = 1
    type = "host"  # Pass through host CPU flags (VT-x/AMD-V)
  }
  
  # Memory
  memory {
    dedicated = 8192  # 8GB
  }
  
  # Disk
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    size         = 50
    discard      = "on"
    ssd          = true
  }
  
  # Network
  network_device {
    bridge = "vmbr0"
  }
  
  # Cloud-init configuration
  initialization {
    ip_config {
      ipv4 {
        address = "${local.control_plane_ips[count.index]}/24"
        gateway = var.network_gateway
      }
    }
    
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
    
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_control_plane[count.index].id
  }
  
  # QEMU guest agent
  agent {
    enabled = true
  }
  
  # Boot order
  boot_order = ["scsi0"]
  
  # Lifecycle
  started = true
  on_boot = true
  
  # Prevent destruction
  lifecycle {
    ignore_changes = [
      started
    ]
  }
}

# =============================================================================
# STANDARD WORKER NODES
# =============================================================================

resource "proxmox_virtual_environment_vm" "workers" {
  count = var.worker_count
  
  name        = "${var.cluster_name}-worker-${count.index + 1}"
  description = "K3s worker node ${count.index + 1}"
  node_name   = var.proxmox_node
  
  tags = concat(local.common_tags, ["worker", "standard"])
  
  clone {
    vm_id = data.proxmox_virtual_environment_vm.template.vm_id
    full  = true
  }
  
  cpu {
    cores = 8
    sockets = 1
    type = "host"
  }
  
  memory {
    dedicated = 16384  # 16GB
  }
  
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    size         = 100
    discard      = "on"
    ssd          = true
  }
  
  network_device {
    bridge = "vmbr0"
  }
  
  initialization {
    ip_config {
      ipv4 {
        address = "${local.worker_ips[count.index]}/24"
        gateway = var.network_gateway
      }
    }
    
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
    
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_workers[count.index].id
  }
  
  agent {
    enabled = true
  }
  
  boot_order = ["scsi0"]
  started    = true
  on_boot    = true
  
  lifecycle {
    ignore_changes = [started]
  }
}

# =============================================================================
# GPU WORKER NODES
# =============================================================================

resource "proxmox_virtual_environment_vm" "gpu_workers" {
  count = var.gpu_worker_count
  
  name        = "${var.cluster_name}-gpu-worker-${count.index + 1}"
  description = "K3s GPU-enabled worker node ${count.index + 1}"
  node_name   = var.proxmox_node
  
  tags = concat(local.common_tags, ["worker", "gpu", "kata-enabled"])
  
  clone {
    vm_id = data.proxmox_virtual_environment_vm.template.vm_id
    full  = true
  }
  
  cpu {
    cores = 8
    sockets = 1
    type = "host"
  }
  
  memory {
    dedicated = 32768  # 32GB for GPU workloads
  }
  
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    size         = 100
    discard      = "on"
    ssd          = true
  }
  
  network_device {
    bridge = "vmbr0"
  }
  
  # GPU Passthrough - This is the critical section
  dynamic "hostpci" {
    for_each = var.gpu_pci_devices
    
    content {
      device  = "hostpci${hostpci.key}"
      id      = hostpci.value.host_pci
      pcie    = hostpci.value.pcie
      rombar  = false
      xvga    = false
    }
  }
  
  # Disable emulated VGA when passing through GPU
  vga {
    type = "none"
  }
  
  initialization {
    ip_config {
      ipv4 {
        address = "${local.gpu_worker_ips[count.index]}/24"
        gateway = var.network_gateway
      }
    }
    
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
    
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_gpu_workers[count.index].id
  }
  
  agent {
    enabled = true
  }
  
  boot_order = ["scsi0"]
  started    = true
  on_boot    = true
  
  lifecycle {
    ignore_changes = [started]
  }
}

# =============================================================================
# CLOUD-INIT FILES
# =============================================================================

resource "proxmox_virtual_environment_file" "cloud_init_control_plane" {
  count = var.control_plane_count
  
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node
  
  source_raw {
    data = templatefile("${path.module}/cloud-init/control-plane.yaml.tpl", {
      hostname     = "${var.cluster_name}-control-${count.index + 1}"
      fqdn         = "${var.cluster_name}-control-${count.index + 1}.local"
      ssh_key      = var.ssh_public_key
      dns_servers  = join(",", var.dns_servers)
      node_role    = "control-plane"
    })
    
    file_name = "cloud-init-control-${count.index + 1}.yaml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_workers" {
  count = var.worker_count
  
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node
  
  source_raw {
    data = templatefile("${path.module}/cloud-init/worker.yaml.tpl", {
      hostname     = "${var.cluster_name}-worker-${count.index + 1}"
      fqdn         = "${var.cluster_name}-worker-${count.index + 1}.local"
      ssh_key      = var.ssh_public_key
      dns_servers  = join(",", var.dns_servers)
      node_role    = "worker"
    })
    
    file_name = "cloud-init-worker-${count.index + 1}.yaml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_gpu_workers" {
  count = var.gpu_worker_count
  
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node
  
  source_raw {
    data = templatefile("${path.module}/cloud-init/gpu-worker.yaml.tpl", {
      hostname     = "${var.cluster_name}-gpu-worker-${count.index + 1}"
      fqdn         = "${var.cluster_name}-gpu-worker-${count.index + 1}.local"
      ssh_key      = var.ssh_public_key
      dns_servers  = join(",", var.dns_servers)
      node_role    = "gpu-worker"
    })
    
    file_name = "cloud-init-gpu-worker-${count.index + 1}.yaml"
  }
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "proxmox_virtual_environment_vm" "template" {
  node_name = var.proxmox_node
  name      = var.template_name
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "control_plane_ips" {
  description = "IP addresses of control plane nodes"
  value = {
    for idx, vm in proxmox_virtual_environment_vm.control_plane :
    vm.name => local.control_plane_ips[idx]
  }
}

output "worker_ips" {
  description = "IP addresses of worker nodes"
  value = {
    for idx, vm in proxmox_virtual_environment_vm.workers :
    vm.name => local.worker_ips[idx]
  }
}

output "gpu_worker_ips" {
  description = "IP addresses of GPU worker nodes"
  value = {
    for idx, vm in proxmox_virtual_environment_vm.gpu_workers :
    vm.name => local.gpu_worker_ips[idx]
  }
}

output "all_nodes" {
  description = "All cluster nodes with their roles and IPs"
  value = merge(
    {
      for idx, vm in proxmox_virtual_environment_vm.control_plane :
      vm.name => {
        ip   = local.control_plane_ips[idx]
        role = "control-plane"
      }
    },
    {
      for idx, vm in proxmox_virtual_environment_vm.workers :
      vm.name => {
        ip   = local.worker_ips[idx]
        role = "worker"
      }
    },
    {
      for idx, vm in proxmox_virtual_environment_vm.gpu_workers :
      vm.name => {
        ip   = local.gpu_worker_ips[idx]
        role = "gpu-worker"
      }
    }
  )
}

output "ansible_inventory_json" {
  description = "Ansible inventory in JSON format"
  value = jsonencode({
    all = {
      children = {
        k3s_server = {
          hosts = {
            for idx, vm in proxmox_virtual_environment_vm.control_plane :
            vm.name => {
              ansible_host = local.control_plane_ips[idx]
              ansible_user = "ubuntu"
            }
          }
        }
        k3s_agent = {
          hosts = merge(
            {
              for idx, vm in proxmox_virtual_environment_vm.workers :
              vm.name => {
                ansible_host = local.worker_ips[idx]
                ansible_user = "ubuntu"
                node_labels  = ["workload-type=general", "sandbox-type=docker,wasm"]
              }
            },
            {
              for idx, vm in proxmox_virtual_environment_vm.gpu_workers :
              vm.name => {
                ansible_host = local.gpu_worker_ips[idx]
                ansible_user = "ubuntu"
                node_labels  = ["workload-type=gpu", "sandbox-type=kata-gpu", "nvidia.com/gpu=true"]
                node_taints  = ["nvidia.com/gpu=true:NoSchedule"]
              }
            }
          )
        }
      }
    }
  })
}
