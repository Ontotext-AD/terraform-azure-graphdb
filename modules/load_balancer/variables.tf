variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

variable "zones" {
  description = "Availability zones"
  type        = list(number)
  default     = [1, 2, 3]
}

variable "backend_port" {
  description = "Backend port for the load balancer rules"
  type        = number
  default     = 7201
}

variable "load_balancer_probe_path" {
  description = "The endpoint to check for GraphDB's health status"
  type        = string
  default     = "/rest/cluster/node/status"
}

variable "load_balancer_probe_interval" {
  description = "Interval in seconds between the health probe checks"
  type        = number
  default     = 10
}

variable "load_balancer_probe_threshold" {
  description = "Number of consecutive health checks to consider the probe passing or failing"
  type        = number
  default     = 1
}
