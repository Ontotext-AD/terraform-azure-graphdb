# App Configuration

variable "app_configuration_name" {
  description = "Name of the App Configuration store for GraphDB"
  type        = string
}

# GraphDB configurations

variable "graphdb_external_address_fqdn" {
  description = "External FQDN for GraphDB"
  type        = string
}

# Managed Data Disks

variable "disk_storage_account_type" {
  description = "Storage account type for the data disks"
  type        = string
}

variable "disk_size_gb" {
  description = "Size of the managed data disk which will be created"
  type        = number
}

variable "disk_iops_read_write" {
  description = "Data disk IOPS"
  type        = number
}

variable "disk_mbps_read_write" {
  description = "Data disk throughput"
  type        = number
}

variable "disk_network_access_policy" {
  description = "Network accesss policy for the managed disks"
  type        = string
}

variable "disk_public_network_access" {
  description = "Public network access enabled for the managed disks"
  type        = bool
}

# Backups

variable "backup_storage_account_name" {
  description = "Storage account name for storing GraphDB backups"
  type        = string
}

variable "backup_storage_container_name" {
  description = "Name of the storage container for GraphDB backups"
  type        = string
}

variable "backup_schedule" {
  description = "Cron expression for the backup job."
  type        = string
}
