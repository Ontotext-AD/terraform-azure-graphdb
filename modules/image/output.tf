output "image_id" {
  description = "The resolved image ID to use for running GraphDB VM instances."
  value       = var.graphdb_image_id != null ? var.graphdb_image_id : data.azurerm_shared_image_version.graphdb.id
}
