variable "resource_name_prefix" {
  description = "Resource name prefix used for naming Azure resources"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where the Jump VM will be deployed"
  type        = string
}

variable "virtual_network_name" {
  description = "Virtual network where the Jump VM will be deployed"
  type        = string
}

variable "jump_subnet_address_prefixes" {
  description = "Address prefixes for the Jump VM subnet"
  type        = list(string)
  default     = ["10.0.4.0/24"]
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks permitted to SSH into the Jump VM"
  type        = list(string)
}

variable "graphdb_subnet_address_prefixes" {
  description = "Address prefixes of the GraphDB VMSS subnet (used to allow outbound SSH)"
  type        = list(string)
}

variable "admin_username" {
  description = "Admin username for the Jump VM"
  type        = string
  default     = "adminuser"
}

variable "ssh_key" {
  description = "Public SSH key for authenticating to the Jump VM"
  type        = string
}

variable "vm_sku" {
  description = "Azure VM SKU for the Jump VM"
  type        = string
}
