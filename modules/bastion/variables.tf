# Common configurations

variable "resource_group_name" {
  description = "Name of the resource group where Bastion will be deployed."
  type        = string
}

# Networking

variable "virtual_network_name" {
  description = "Virtual network where Bastion will be deployed"
  type        = string
}

variable "resource_name_prefix" {
  description = "Resource name prefix"
  type        = string
}

