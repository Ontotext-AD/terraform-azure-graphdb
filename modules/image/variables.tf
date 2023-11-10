variable "graphdb_version" {
  description = "GraphDB version to deploy"
  type        = string
  default     = "10.4.0"
}

variable "graphdb_image_id" {
  description = "Image ID to use for running GraphDB VM instances. If left unspecified, Terraform will use the image from our public Compute Gallery."
  type        = string
  default     = null
}
