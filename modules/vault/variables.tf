# Common configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

# Networking

variable "nacl_subnet_ids" {
  description = "List of subnet identifiers allowed to access the key vault internally over a service link"
  type        = list(string)
  default     = []
}

variable "nacl_ip_rules" {
  description = "List of CIDR blocks allowed to access the key vault from the internet"
  type        = list(string)
  default     = []
}

# Key Vault

# Enable only for production
variable "key_vault_enable_purge_protection" {
  description = "Prevents purging the key vault and its contents by soft deleting it. It will be deleted once the soft delete retention has passed."
  type        = bool
  default     = false
}

variable "key_vault_retention_days" {
  description = "Retention period in days during which soft deleted secrets are kept"
  type        = number
  default     = 7
}

# Role assigment

variable "assign_administrator_role" {
  description = "Assign 'Key Vault Administrator' role to the current client. Needed in order to create secrets."
  type        = bool
  default     = true
}
