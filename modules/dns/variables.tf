# General configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string
}

variable "virtual_network_id" {
  description = "Virtual network the DNS will be linked to"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name where the DNS zone will be created"
  type        = string
}
