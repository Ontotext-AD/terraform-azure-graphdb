# Common configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string
}

variable "resource_group_id" {
  description = "Identifier of the resource group where GraphDB will be deployed."
  type        = string
}

# Identity

variable "identity_principal_id" {
  description = "Principal identifier of a user assigned identity for assigning permissions"
  type        = string
}

# Key Vault

variable "key_vault_id" {
  description = "Identifier of a Key Vault for storing GraphDB configurations"
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
