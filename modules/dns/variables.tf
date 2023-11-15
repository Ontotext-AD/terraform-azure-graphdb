variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.resource_name_prefix)) && !can(regex("^-", var.resource_name_prefix))
    error_message = "Resource name prefix cannot start with a hyphen and can only contain letters, numbers, and hyphens."
  }
}

variable "zone_dns_name" {
  description = "DNS name for the private DNS zone in Azure"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name where the DNS zone will be created"
  type        = string
}

variable "identity_name" {
  description = "Name of a user assigned identity with permissions"
  type        = string
}

variable "zone_dns_name" {
  description = "DNS name for the private DNS zone in Azure"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name where the DNS zone will be created"
  type        = string
}
