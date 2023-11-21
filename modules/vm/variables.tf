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

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

variable "resource_group_id" {
  description = "Identifier of the resource group where GraphDB will be deployed."
  type        = string
}

# Networking

variable "graphdb_subnet_id" {
  description = "Identifier of the subnet where GraphDB will be deployed"
  type        = string
}

variable "graphdb_subnet_cidr" {
  description = "CIDR of the subnet where GraphDB will be deployed"
  type        = string
}

# Security

variable "identity_id" {
  description = "Identifier of a user assigned identity with permissions"
  type        = string
}

variable "identity_principal_id" {
  description = "Principal identifier of a user assigned identity with permissions"
  type        = string
}

variable "key_vault_name" {
  description = "Name of a Key Vault containing GraphDB configurations"
  type        = string
}

# Application Gateway

variable "application_gateway_backend_address_pool_ids" {
  description = "Array of identifiers of load balancer backend pools for the GraphDB nodes"
  type        = list(string)
  default     = []
}

# GraphDB configurations

variable "graphdb_external_address_fqdn" {
  description = "External FQDN for GraphDB"
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

variable "source_ssh_blocks" {
  description = "CIDR blocks to allow SSH traffic from."
  type        = list(string)
  default     = null
}

variable "custom_user_data" {
  description = "Custom user data script used during the cloud init phase in the GraphDB VMs. Should be in base64 encoding."
  type        = string
  default     = null
}

# Managed Data Disks

variable "disk_size_gb" {
  description = "Size of the managed data disk which will be created"
  type        = number
  default     = null
}

variable "data_disk_performance_tier" {
  description = "Performance tier of the managed data disk"
  type        = string
  default     = null
}
