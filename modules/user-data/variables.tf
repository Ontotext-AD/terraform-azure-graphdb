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

variable "disk_size_gb" {
  description = "Size of the managed data disk which will be created"
  type        = number
  default     = null
}

variable "disk_iops_read_write" {
  description = "Data disk IOPS"
  type        = number
  default     = null
}

variable "disk_mbps_read_write" {
  description = "Data disk throughput"
  type        = number
  default     = null
}

# Backups

variable "backup_storage_container_url" {
  description = "URL to a storage container for uploading GraphDB backups"
  type        = string
}

variable "backup_schedule" {
  description = "Cron expression for the backup job."
  type        = string
}
