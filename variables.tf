# General configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.resource_name_prefix)) && !can(regex("^-", var.resource_name_prefix))
    error_message = "Resource name prefix cannot start with a hyphen and can only contain letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "zones" {
  description = "Availability zones to use for resource deployment and HA"
  type        = list(number)
  default     = [1, 2, 3]
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "lock_resources" {
  description = "Enables a delete lock on the resource group to prevent accidental deletions."
  type        = bool
  default     = true
}

# Networking

variable "virtual_network_address_space" {
  description = "Virtual network address space CIDRs."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "app_gateway_subnet_address_prefix" {
  description = "Subnet address prefix CIDRs where the application gateway will reside."
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "graphdb_subnet_address_prefix" {
  description = "Subnet address prefix CIDRs where GraphDB VMs will reside."
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "management_cidr_blocks" {
  description = "CIDR blocks allowed to perform management operations such as connecting to Bastion or Key Vault."
  type        = list(string)
}

# TLS

variable "tls_certificate_path" {
  description = "Path to a TLS certificate that will be imported in Azure Key Vault and used in the Application Gateway TLS listener for GraphDB."
  type        = string
}

variable "tls_certificate_password" {
  description = "TLS certificate password for password protected certificates."
  type        = string
  default     = null
}

# Key Vault

# Enable only for production
variable "key_vault_enable_purge_protection" {
  description = "Prevents purging the key vault and its contents by soft deleting it. It will be deleted once the soft delete retention has passed."
  type        = bool
  default     = false
}

variable "key_vault_retention_days" {
  description = "Retention period in days during which soft deleted secrets are kept"
  type        = number
  default     = 30
}

# GraphDB

variable "graphdb_version" {
  description = "GraphDB version to deploy"
  type        = string
  default     = "10.4.1"
}

variable "graphdb_image_id" {
  description = "Image ID to use for running GraphDB VM instances. If left unspecified, Terraform will use the image from our public Compute Gallery."
  type        = string
  default     = null
}

# GraphDB configurations

variable "graphdb_license_path" {
  description = "Local path to a file, containing a GraphDB Enterprise license."
  type        = string
}

variable "graphdb_cluster_token" {
  description = "Secret token used to secure the internal GraphDB cluster communication. Will generate one if left undeclared."
  type        = string
  default     = null
}

variable "graphdb_password" {
  description = "Secret token used to access GraphDB cluster."
  type        = string
  default     = null
}

variable "graphdb_properties_path" {
  description = "Path to a local file containing GraphDB properties (graphdb.properties) that would be appended to the default in the VM."
  type        = string
  default     = null
}

variable "graphdb_java_options" {
  description = "GraphDB options to pass to GraphDB with GRAPHDB_JAVA_OPTS environment variable."
  type        = string
  default     = null
}

# GraphDB VM

variable "node_count" {
  description = "Number of GraphDB nodes to deploy in ASG"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "Azure instance type"
  type        = string
}

variable "ssh_key" {
  description = "Public key for accessing the GraphDB instances"
  type        = string
  default     = null
}

variable "custom_graphdb_vm_user_data" {
  description = "Custom user data script used during the cloud init phase in the GraphDB VMs. Should be in base64 encoding."
  type        = string
  default     = null
}

# Storage account

variable "storage_account_tier" {
  description = "Specify the performance and redundancy characteristics of the Azure Storage Account that you are creating"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Specify the data redundancy strategy for your Azure Storage Account"
  type        = string
  default     = "ZRS"
}

# Backup configurations

variable "backup_schedule" {
  description = "Cron expression for the backup job."
  type        = string
  default     = "0 0 * * *"
}

# Data disks

variable "disk_size_gb" {
  description = "Size of the managed data disk which will be created"
  type        = number
  default     = 500
}

variable "disk_iops_read_write" {
  description = "Data disk IOPS"
  type        = number
  default     = 7500
}

variable "disk_mbps_read_write" {
  description = "Data disk throughput"
  type        = number
  default     = 250
}

# Bastion

variable "deploy_bastion" {
  description = "Deploy bastion module"
  type        = bool
  default     = false
}

variable "bastion_subnet_address_prefix" {
  description = "Bastion subnet address prefix"
  type        = list(string)
  default     = ["10.0.3.0/27"]
}
