variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where the Log Analytics workspace will be deployed."
  type        = string
}

variable "vmss_resource_id" {
  description = "ID of the VMSS instance"
  type        = string
}

variable "cpu_monitoring_frequency" {
  description = "The evaluation frequency of this Metric Alert. Possible values are PT1M, PT5M, PT15M, PT30M and PT1H."
  type        = string
  default     = "PT5M"
}

variable "cpu_monitoring_window_size" {
  description = "The period of time that is used to monitor alert activity. Value must be greater than frequency. Possible values are PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H and P1D"
  type        = string
  default     = "PT30M"
}

variable "cpu_monitoring_auto_mitigate" {
  description = "Should the alerts in this Metric Alert be auto resolved? Defaults to true"
  type        = bool
  default     = true
}

variable "cpu_monitoring_severity" {
  description = "The severity of this Metric Alert. Possible values are 0, 1, 2, 3 and 4."
  type        = number
  default     = 2
}

variable "cpu_monitoring_threshold" {
  description = "The criteria threshold value that activates the alert"
  type        = number
  default     = 90
}

variable "memory_monitoring_frequency" {
  description = "The evaluation frequency of this Metric Alert. Possible values are PT1M, PT5M, PT15M, PT30M and PT1H."
  type        = string
  default     = "PT5M"
}

variable "memory_monitoring_window_size" {
  description = "The period of time that is used to monitor alert activity. Value must be greater than frequency. Possible values are PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H and P1D"
  type        = string
  default     = "PT30M"
}

variable "memory_monitoring_auto_mitigate" {
  description = "Should the alerts in this Metric Alert be auto resolved? Defaults to true"
  type        = bool
  default     = true
}

variable "memory_monitoring_severity" {
  description = "The severity of this Metric Alert. Possible values are 0, 1, 2, 3 and 4."
  type        = number
  default     = 2
}

variable "memory_monitoring_threshold" {
  description = "The criteria threshold value that activates the alert. The value is in bytes"
  type        = number
  default     = 4000000000
}

variable "log_analytics_workspace_id" {
  description = "Log analytics workspace identifier"
  type        = string
}

variable "disk_space_monitoring_severity" {
  description = "The severity of this Metric Alert. Possible values are 0, 1, 2, 3 and 4."
  type        = number
  default     = 0
}

variable "disk_space_monitoring_frequency" {
  description = "The evaluation frequency of this Metric Alert. Possible values are PT1M, PT5M, PT15M, PT30M and PT1H."
  type        = string
  default     = "PT1M"

}
variable "disk_space_monitoring_window_size" {
  description = "The period of time that is used to monitor alert activity. Value must be greater than frequency. Possible values are PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H and P1D"
  type        = string
  default     = "PT5M"
}
variable "disk_space_monitoring_threshold" {
  description = "The criteria threshold value that activates the alert. The value is in percents"
  type        = number
  default     = 10
}
variable "disk_space_monitoring_auto_mitigate" {
  description = "Should the alerts in this Metric Alert be auto resolved? Defaults to true"
  type        = bool
  default     = true
}

