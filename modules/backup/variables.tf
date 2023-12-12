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
  description = "Specifies the name of the Azure resource group in which the Azure Storage Account will be created"
  type        = string
}

# Networking

variable "nacl_subnet_ids" {
  description = "List of subnet identifiers allowed to access the storage account internally over a service link"
  type        = list(string)
  default     = []
}

variable "nacl_ip_rules" {
  description = "List of CIDR blocks allowed to access the storage account"
  type        = list(string)
  default     = []
}

# Storage specifics

variable "storage_account_kind" {
  description = "Specifies the type of the storage account."
  type        = string
  default     = "StorageV2"
}

variable "storage_account_tier" {
  description = "Specify the performance and redundancy characteristics of the Azure Storage Account that you are creating"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Specify the data redundancy strategy for your Azure Storage Account"
  type        = string
  default     = "ZRS"
}
