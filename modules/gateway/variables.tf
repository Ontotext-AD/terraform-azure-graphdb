# General configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming AWS resources"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "zones" {
  description = "Availability zones for the public IP address."
  type        = list(number)
  default     = [1, 2, 3]
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

# Networking

variable "gateway_subnet_id" {
  description = "Subnet identifier where the Application Gateway will be deployed"
  type        = string
}

variable "gateway_subnet_address_prefix" {
  description = "Address prefix of the subnet where the Application Gateway will be deployed"
  type        = string
}

# Application gateway specific configurations

variable "gateway_enable_private_access" {
  description = "Enable or disable private access to the application gateway"
  type        = bool
}

variable "gateway_min_capacity" {
  description = "Minimum capacity for the Application Gateway autoscaling"
  type        = number
  default     = 1
}

variable "gateway_max_capacity" {
  description = "Maximum capacity for the Application Gateway autoscaling"
  type        = number
  default     = 2
}

variable "gateway_ssl_policy_profile" {
  description = "The predefined SSL policy to use in the Application Gateway"
  type        = string
  default     = "AppGwSslPolicy20220101S"
}

variable "gateway_backend_port" {
  description = "Backend port for the Application Gateway rules"
  type        = number
  default     = 7201
}

variable "gateway_backend_path" {
  description = "Backend path for the Application Gateway rules"
  type        = string
  default     = "/"
}

variable "gateway_backend_protocol" {
  description = "Backend protocol for Application Gateway rules"
  type        = string
  default     = "Http"
}

variable "gateway_backend_request_timeout" {
  description = "Backend request timeout in minutes"
  type        = number
  default     = 86400 # 1 day
}

# HTTP probe specifics

variable "gateway_probe_path" {
  description = "The endpoint to check for GraphDB's health status"
  type        = string
  default     = "/rest/cluster/node/status"
}

variable "gateway_probe_port" {
  description = "Backend port for the health probe checks"
  type        = number
  default     = 7200
}

variable "gateway_probe_interval" {
  description = "Interval in seconds between the health probe checks"
  type        = number
  default     = 10
}

variable "gateway_probe_timeout" {
  description = "Timeout in seconds for the health probe checks"
  type        = number
  default     = 1
}

variable "gateway_probe_threshold" {
  description = "Number of consecutive health checks to consider the probe passing or failing"
  type        = number
  default     = 2
}

# TLS certificate

variable "gateway_tls_certificate_secret_id" {
  description = "Secret identifier of the TLS certificate in the Key Vault."
  type        = string
}

variable "gateway_tls_identity_id" {
  description = "Identifier of a user assigned identity having access to the TLS certificate in the Key Vault"
  type        = string
}

# Private Link

variable "gateway_enable_private_link_service" {
  description = "Set to true to enable Private Link service, false to disable"
  type        = bool
}

variable "gateway_private_link_subnet_id" {
  description = "Identifier of a subnet where the Private Link will be deployed, if enabled"
  type        = string
  default     = null
}
