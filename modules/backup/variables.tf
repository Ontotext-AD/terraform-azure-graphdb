variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming AWS resources"
  type        = string
}

variable "resource_group_name" {
  description = "Specifies the name of the Azure resource group in which the Azure Storage Account will be created"
  type        = string
}

variable "account_tier" {
  default     = "Standard"
  description = "Specify the performance and redundancy characteristics of the Azure Storage Account that you are creating"
  type        = string
}

variable "account_replication_type" {
  default     = "LRS"
  description = "Specify the data redundancy strategy for your Azure Storage Account"
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "identity_name" {
  description = "Name of a user assigned identity for assigning permissions"
  type        = string
}