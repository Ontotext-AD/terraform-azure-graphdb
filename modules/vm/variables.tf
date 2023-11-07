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

variable "network_interface_name" {
  description = "Network interface where GraphDB will be deployed"
  type        = string
}

variable "graphdb_subnet_name" {
  description = "Name of the subnet where GraphDB will be deployed"
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

variable "zones" {
  description = "Availability zones"
  type        = list(number)
  default     = [1, 3]
}

variable "load_balancer_backend_address_pool_id" {
  description = "Identifier of the load balancer backend pool for GraphDB nodes"
  type        = string
}

variable "load_balancer_fqdn" {
  description = "FQDN of the load balancer for GraphDB"
  type        = string
}
