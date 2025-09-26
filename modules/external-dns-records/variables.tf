variable "zone_name" {
  description = "DNS zone name (e.g., example.com)."
  type        = string
}

variable "private_zone" {
  description = "Create Private DNS (true) or Public DNS (false)."
  type        = bool
  default     = false
}

variable "public_zone" {
  description = "Create Public DNS (true) or Private DNS (false). Deprecated, use private_zone instead."
  type        = bool
  default     = true
}

variable "create_resource_group" {
  description = "Whether to create the resource group."
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Resource Group name where the zone will reside."
  type        = string
}

variable "resource_group_location" {
  description = "Resource Group location (used if create_resource_group = true)."
  type        = string
}

# Private zone VNet links: map of objects
variable "private_zone_vnet_links" {
  description = <<EOT
Map of VNet links for private zones. Key = logical link name.
Fields:
- name (optional): Override link name.
- virtual_network_id (required)
- registration_enabled (optional, default false)
EOT
  type = map(object({
    name                 = optional(string)
    virtual_network_id   = string
    registration_enabled = optional(bool)
  }))
  default = {}
}

# ---------- Records common types ----------

variable "a_records" {
  description = <<EOT
Map of A records. Key = relative record set name (e.g., "@", "www").
Fields:
- ttl (number)
- records (optional list of IPv4)
- target_resource_id (optional, public zone only – alias to public IP/ALB)
EOT
  type = map(object({
    ttl                = number
    records            = optional(list(string))
    target_resource_id = optional(string)
  }))
  default = {}
}

variable "cname_records" {
  description = "Map of CNAME records. 'record' must be a single FQDN."
  type = map(object({
    ttl                = number
    record             = string
    target_resource_id = optional(string) # only in public zones
  }))
  default = {}
}

variable "txt_records" {
  description = "Map of TXT records."
  type = map(object({
    ttl = number
    records = list(object({
      value = string
    }))
  }))
  default = {}
}

variable "mx_records" {
  description = "Map of MX records."
  type = map(object({
    ttl = number
    records = list(object({
      preference = number
      exchange   = string
    }))
  }))
  default = {}
}

variable "ns_records" {
  description = "Map of NS records (public zones only)."
  type = map(object({
    ttl     = number
    records = list(string)
  }))
  default = {}
}

variable "srv_records" {
  description = "Map of SRV records."
  type = map(object({
    ttl = number
    records = list(object({
      priority = number
      weight   = number
      port     = number
      target   = string
    }))
  }))
  default = {}
}


