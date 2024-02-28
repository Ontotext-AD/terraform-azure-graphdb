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

variable "virtual_network_name" {
  description = "Virtual network where Bastion will be deployed"
  type        = string
}

variable "gateway_subnet_id" {
  description = "Subnet identifier where the application gateway will reside"
  type        = string
}

variable "gateway_subnet_address_prefixes" {
  description = "Subnet address prefix CIDRs where the application gateway will reside"
  type        = list(string)
}

variable "gateway_allowed_address_prefix" {
  description = "Address prefix allowed for connecting to the application gateway"
  type        = string
}

variable "gateway_allowed_address_prefixes" {
  description = "Address prefixes allowed for connecting to the application gateway"
  type        = list(string)
  default     = []
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
  description = "Backend request timeout in seconds"
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
  description = "Secret identifier of a TLS certificate from a Key Vault."
  type        = string
}

variable "gateway_tls_certificate_identity_id" {
  description = "Identifier of a user assigned identity having access to the TLS certificate in the Key Vault"
  type        = string
}

# Private Link

variable "gateway_enable_private_link_service" {
  description = "Set to true to enable Private Link service, false to disable"
  type        = bool
}

variable "gateway_private_link_subnet_address_prefixes" {
  description = "Subnet address prefixes where the Application Gateway Private Link will reside, if enabled"
  type        = list(string)
  default     = []
}

variable "gateway_private_link_service_network_policies_enabled" {
  description = "Enable or disable private link service network policies"
  type        = string
  default     = false
}

# Public IP configurations

variable "gateway_pip_idle_timeout" {
  description = "Specifies the timeout for the TCP idle connection"
  type        = number
  default     = 5
}

# Proxy buffer configurations
variable "gateway_global_request_buffering_enabled" {
  description = "Whether Application Gateway's Request buffer is enabled."
  type        = bool
}

variable "gateway_global_response_buffering_enabled" {
  description = "Whether Application Gateway's Response buffer is enabled."
  type        = bool
}
