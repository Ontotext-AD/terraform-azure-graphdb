# Common configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "zones" {
  description = "Availability zones"
  type        = list(number)
  default     = [1, 2, 3]
}

variable "resource_group_id" {
  description = "Identifier of the resource group where GraphDB will be deployed."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

# Networking

variable "graphdb_subnet_id" {
  description = "Identifier of the subnet where GraphDB will be deployed"
  type        = string
}

variable "application_security_group_ids" {
  description = "Identifiers of application security groups to be applied to the GraphDB VMSS instances"
  type        = list(string)
  default     = []
}

# Application Gateway

variable "application_gateway_backend_address_pool_ids" {
  description = "Array of identifiers of load balancer backend pools for the GraphDB nodes"
  type        = list(string)
  default     = []
}

# Key Vault

variable "key_vault_id" {
  description = "Identifier of a Key Vault for storing GraphDB configurations"
  type        = string
}

# App Configuration

variable "app_configuration_id" {
  description = "Identifier of the App Configuration store for GraphDB"
  type        = string
}

# Backups storage

variable "backups_storage_container_id" {
  description = "Identifier of the storage container for GraphDB backups"
  type        = string
}

# DNS

variable "private_dns_zone" {
  description = "Identifier of a Private DNS zone"
  type        = string
}

# GraphDB VM

variable "node_count" {
  description = "Number of GraphDB nodes to deploy in ASG"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "Azure instance type"
  type        = string
}

variable "image_id" {
  description = "Image ID to use with GraphDB instances"
  type        = string
}

variable "ssh_key" {
  description = "Public key for accessing the GraphDB instances"
  type        = string
  default     = null
}

variable "user_data_script" {
  description = "User data script used during the cloud init phase in the GraphDB VMs. Should be in base64 encoding."
  type        = string
}

variable "encryption_at_host" {
  description = "Enables encryption at rest on the VM host"
  type        = bool
  default     = true
}
