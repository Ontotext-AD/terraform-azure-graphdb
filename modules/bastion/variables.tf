# Common configurations

variable "resource_name_prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where Bastion will be deployed."
  type        = string
}

# Networking

variable "virtual_network_name" {
  description = "Virtual network where Bastion will be deployed"
  type        = string
}

variable "bastion_subnet_address_prefix" {
  description = "Bastion subnet address prefix"
  type        = list(string)
  default     = ["10.0.3.0/27"]
}

variable "bastion_allowed_cidr_blocks" {
  description = "CIDR blocks allowed for connecting to Bastion"
  type        = list(string)
}
