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

variable "appi_retention_in_days" {
  description = "Specifies the retention period in days."
  type        = number
  default     = 30
}

variable "appi_internet_query_enabled" {
  description = "Should the Application Insights component support querying over the Public Internet"
  type        = bool
  default     = true
}

variable "appi_application_type" {
  description = "Specifies the type of Application Insights to create"
  type        = string
  default     = "java"
}

variable "web_test_availability_enabled" {
  description = "Should the availability web test be enabled"
  type        = bool
  default     = true
}

variable "web_test_availability_expected_status_code" {
  description = "Expected response status code of the availability test"
  type        = number
  default     = 200
}

variable "web_test_availability_request_url" {
  description = "URL for the availability test"
  type        = string
}

variable "web_test_availability_content_match" {
  description = "The availability web test response should contain the value in the response"
  type        = string
  default     = "\"nodeState\":\"LEADER\""
}

# TODO change to true if prod deployment
variable "web_test_ssl_check_enabled" {
  description = "Should the SSL check be enabled?"
  type        = bool
  default     = false
}

variable "web_test_geo_locations" {
  description = "A list of geo locations the test will be executed from"
  type        = list(string)
}

variable "web_test_frequency" {
  description = "Interval in seconds between tests. Valid options are 300, 600 and 900. Defaults to 300."
  type        = number
  default     = 300
}

variable "web_test_timeout" {
  description = "Seconds until this WebTest will timeout and fail."
  type        = number
  default     = 30
}

variable "monitor_reader_principal_id" {
  description = "Principal(Object) ID of a user/group which would receive notifications from alerts."
  type        = string
}

variable "ag_push_notification_accounts" {
  description = "List of accounts to receive push notifications"
  type        = list(string)
  default     = []
}

variable "ag_arm_role_receiver_role_id" {
  description = "Principal(Object) ID of the role which will receive e-mails. Defaults to the owner built-in role"
  type        = string
  default     = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
}

variable "enable_alerts" {
  description = "Should the alerts be enabled"
  type        = bool
  default     = true
}

variable "enable_smart_detection_rules" {
  description = "Should smart detection rule be enabled"
  type        = bool
  default     = true
}

variable "al_low_memory_warning_threshold" {
  description = "Percentage of available used heap memory to monitor for"
  type        = number
  default     = 90
}
