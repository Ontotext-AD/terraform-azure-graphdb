# General configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming AWS resources"
  type        = string
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

# Key Vault

variable "key_vault_name" {
  description = "Name of a Key Vault containing GraphDB configurations"
  type        = string
}

# TLS

variable "tls_certificate" {
  description = "TLS certificate in base64 encoding to be imported in Azure Key Vault."
  type        = string
}

variable "tls_certificate_password" {
  description = "TLS certificate password for password protected certificates."
  type        = string
  default     = null
}
