variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

variable "identity_name" {
  description = "Name of a user assigned identity for assigning permissions"
  type        = string
}

variable "key_vault_name" {
  description = "Name of a Key Vault containing GraphDB configurations"
  type        = string
}

variable "graphdb_license_path" {
  description = "Local path to a file, containing a GraphDB Enterprise license."
  type        = string
}

variable "graphdb_license_secret_name" {
  description = "Name of the Key Vault secret that contains the GraphDB license."
  type        = string
  default     = "graphdb-license"
}
