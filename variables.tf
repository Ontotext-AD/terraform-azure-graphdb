variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type = string
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "graphdb_subnets" {
  description = "Private subnets where GraphDB will be deployed"
  type        = list(string)
}

variable "lb_subnets" {
  description = "The subnets used by the load balancer. If internet-facing use the public subnets, private otherwise."
  type        = list(string)
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

variable "graphdb_version" {
  description = "GraphDB version to deploy"
  type        = string
  default     = "10.4.0"
}
