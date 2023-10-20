variable "azure_region" {
  default     = "eastus"
  description = "Location of the resource group."
  type = string
}

variable "rg_name" {
  description = "Resource group name."
  type = string
}

variable "prefix" {
  type        = string
  default     = "win-vm-iis"
  description = "Prefix of the resource name"
}

variable "graphdb_subnets" {
  description = "Private subnets where GraphDB will be deployed"
  type        = list(string)
}

variable "lb_subnets" {
  description = "The subnets used by the load balancer. If internet-facing use the public subnets, private otherwise."
  type        = list(string)
}

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming AWS resources"
  type        = string
}

variable "allowed_inbound_cidrs" {
  description = "List of CIDR blocks to permit inbound traffic from to load balancer"
  type        = list(string)
  default     = null
}

variable "allowed_inbound_cidrs_ssh" {
  description = "List of CIDR blocks to give SSH access to GraphDB nodes"
  type        = list(string)
  default     = null
}

variable "network_interface_id" {
  description = "Network ID where GraphDB will be deployed"
  type        = string
}

variable "node_count" {
  description = "Number of GraphDB nodes to deploy in ASG"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "Azure instance type"
  type        = string
}

variable "image_id" {
  description = "Image ID to use with GraphDB instances"
  type        = string
  default     = null
}