# Common configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Specifies the name of the Azure resource group in which the Azure Storage Account will be created"
  type        = string
}

# Identity

variable "identity_name" {
  description = "Name of a user assigned identity for assigning permissions"
  type        = string
}

variable "identity_principal_id" {
  description = "Principal identifier of a user assigned identity for assigning permissions"
  type        = string
}

# Storage specifics

variable "storage_account_tier" {
  default     = "Standard"
  description = "Specify the performance and redundancy characteristics of the Azure Storage Account that you are creating"
  type        = string
}

variable "storage_account_replication_type" {
  default     = "LRS"
  description = "Specify the data redundancy strategy for your Azure Storage Account"
}
