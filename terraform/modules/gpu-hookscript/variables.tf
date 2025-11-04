variable "gpu_worker_count" {
  description = "Number of GPU worker VMs to create"
  type        = number
  default     = 1
}

variable "cluster_name" {
  description = "Name of the k3s cluster"
  type        = string
  default     = "rbaas"
}

variable "proxmox_node" {
  description = "Proxmox node to deploy VMs on"
  type        = string
}

variable "proxmox_storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
}

variable "proxmox_bridge" {
  description = "Proxmox network bridge for VMs"
  type        = string
}

variable "use_gpu_hookscript" {
  description = "Use dynamic GPU binding (recommended)"
  type        = bool
  default     = true
}

data "proxmox_virtual_environment_vm" "template" {
  name      = "ubuntu-2204-cloudinit-template"
  node_name = var.proxmox_node
}

locals {
  common_tags = ["rbaas", "k3s"]
}
