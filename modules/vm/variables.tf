variable "azure_region" {
  default     = "eastus"
  description = "Location of the resource group."
  type        = string
}

variable "rg_name" {
  description = "Resource group name."
  type        = string
}

variable "graphdb_subnets" {
  description = "Private subnets where GraphDB will be deployed"
  type        = list(string)
}

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming AWS resources"
  type        = string
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