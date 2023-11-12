# General configurations

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

# Security dependencies

variable "identity_name" {
  description = "Name of a user assigned identity for assigning permissions"
  type        = string
}

variable "key_vault_name" {
  description = "Name of a Key Vault containing GraphDB configurations"
  type        = string
}

# GraphDB configurations

variable "graphdb_license_path" {
  description = "Local path to a file, containing a GraphDB Enterprise license."
  type        = string
}

variable "graphdb_license_secret_name" {
  description = "Name of the Key Vault secret that contains the GraphDB license."
  type        = string
  default     = "graphdb-license"
}

variable "graphdb_cluster_token" {
  description = "Secret token used to secure the internal GraphDB cluster communication."
  type        = string
  default     = null
}

variable "graphdb_cluster_token_name" {
  description = "Name of the Key Vault secret that contains the GraphDB cluster secret token."
  type        = string
  default     = "graphdb-cluster-token"
}

variable "graphdb_properties_path" {
  description = "Path to a local file containing GraphDB properties (graphdb.properties) that would be appended to the default in the VM."
  type        = string
  default     = null
}

variable "graphdb_properties_secret_name" {
  description = "Name of the Key Vault secret that contains the GraphDB properties."
  type        = string
  default     = "graphdb-properties"
}

variable "graphdb_java_options" {
  description = "GraphDB options to pass to GraphDB with GRAPHDB_JAVA_OPTS environment variable."
  type        = string
  default     = null
}

variable "graphdb_java_options_secret_name" {
  description = "Name of the Key Vault secret that contains the GraphDB GRAPHDB_JAVA_OPTS configurations."
  type        = string
  default     = "graphdb-java-options"
}
