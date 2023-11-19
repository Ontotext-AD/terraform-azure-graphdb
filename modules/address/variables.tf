# General configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming AWS resources"
  type        = string
}

variable "zones" {
  description = "Availability zones for the public IP address."
  type        = list(number)
  default     = [1, 2, 3]
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}
