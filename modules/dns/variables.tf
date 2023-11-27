variable "resource_group_name" {
  description = "Resource group name where the DNS zone will be created"
  type        = string
}

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.resource_name_prefix)) && !can(regex("^-", var.resource_name_prefix))
    error_message = "Resource name prefix cannot start with a hyphen and can only contain letters, numbers, and hyphens."
  }
}

variable "identity_name" {
  description = "Name of a user assigned identity with permissions"
  type        = string
}

variable "virtual_network_id" {
  description = "Virtual network the DNS will be linked to"
  type        = string
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "identity_principal_id" {
  description = "Principal identifier of a user assigned identity with permissions"
  type        = string
}
