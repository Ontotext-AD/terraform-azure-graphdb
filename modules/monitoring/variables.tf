variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where the Log Analytics workspace will be deployed."
  type        = string
}

variable "workspace_retention_in_days" {
  description = "The workspace data retention in days. Possible values are either 7 (Free Tier only) or range between 30 and 730."
  type        = number
  default     = 30
}

variable "workspace_sku" {
  description = "Specifies the SKU of the Log Analytics Workspace. Possible values are Free, PerNode, Premium, Standard, Standalone, Unlimited, CapacityReservation, and PerGB2018 (new SKU as of 2018-04-03). Defaults to PerGB2018."
  type        = string
  default     = "PerGB2018"
}

variable "data_collection_kind" {
  description = "The OS of the machine running GraphDB"
  type        = string
  default     = "Linux"
}

variable "dce_public_network_access_enabled" {
  description = "Whether network access from public internet to the Data Collection Endpoint are allowed."
  type        = bool
  default     = true
}

variable "vmss_resource_id" {
  description = "ID of the VMSS instance"
  type        = string
}

variable "performance_counter_sampling_frequency_in_seconds" {
  description = "Sampling frequency in seconds"
  type        = number
  default     = 60
}

variable "main_log_table_retentionInDays" {
  description = "GraphDB main log table retention in days"
  type        = number
  default     = 30
}

variable "main_log_table_totalRetentionInDays" {
  description = "GraphDB main log table total retention in days"
  type        = number
  default     = 30
}

variable "custom_table_plan" {
  description = "Table plan for the main log table: possible options are Analytics and Basic"
  type        = string
  default     = "Analytics" # var.custom_table_plan
}
