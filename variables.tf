variable "resource_group_location" {
  type        = string
  default     = "eastus"
  description = "Location of the resource group."
}

variable "resource_group_name_prefix" {
  type        = string
  default     = "rg"
  description = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
}

variable "vpc_id" {
  type        = string
  description = "Network ID where GraphDB will be deployed"
}

variable "azure_region" {
  default     = "eastus"
  description = "Location of the resource group."
  type        = string
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

variable "rg_name" {
  description = "Resource group name."
  type        = string
}

variable "ssh_key" {
  description = "Public key for accessing the GraphDB instances"
  type        = string
  default     = null
}

variable "source_ssh_blocks" {
  description = "CIDR blocks to allow SSH traffic from."
  type        = list(string)
  default     = null
}