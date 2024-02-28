# Common configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
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

# App Configuration

# Enable only for production
variable "app_config_enable_purge_protection" {
  description = "Prevents purging the App Configuration and its keys by soft deleting it. It will be deleted once the soft delete retention has passed."
  type        = bool
  default     = false
}

variable "app_config_retention_days" {
  description = "Retention period in days during which soft deleted keys are kept"
  type        = number
  default     = 7
}

# Role assigment

variable "admin_security_principle_id" {
  description = "UUID of a user or service principle that will become App Configuration data owner"
  type        = string
  default     = null
}

# Log Analytics Workspace

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID used for saving key vault diagnostics"
  type        = string
}
