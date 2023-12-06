# General configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming AWS resources"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

# Key Vault

variable "key_vault_id" {
  description = "Identifier of a Key Vault for storing secrets and certificates"
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
