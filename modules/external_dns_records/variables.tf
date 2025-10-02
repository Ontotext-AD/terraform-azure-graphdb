variable "zone_name" {
  description = "DNS zone name (e.g., example.com)."
  type        = string
}

variable "private_zone" {
  description = "Create Private DNS (true) or Public DNS (false)."
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Resource Group name where the zone will reside."
  type        = string
}

variable "private_zone_vnet_links" {
  description = "Map of VNet links for private zones."
  type = map(object({
    name                 = optional(string)
    virtual_network_id   = string
    registration_enabled = optional(bool)
  }))
  default = {}
}

variable "a_records_list" {
  description = "List of A records."
  type = list(object({
    name               = string
    ttl                = number
    records            = optional(list(string))
    target_resource_id = optional(string)
  }))
  default = []
}

variable "cname_records_list" {
  description = "List of CNAME records."
  type = list(object({
    name               = string
    ttl                = number
    record             = string
    target_resource_id = optional(string)
  }))
  default = []
}
