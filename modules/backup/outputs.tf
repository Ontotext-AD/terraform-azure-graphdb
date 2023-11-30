output "storage_account_id" {
  description = "Storage account identifier for storing GraphDB backups"
  value       = azurerm_storage_account.graphdb_backup.id
}

output "storage_account_name" {
  description = "Storage account name for storing GraphDB backups"
  value       = azurerm_storage_account.graphdb_backup.name
}

output "storage_container_id" {
  description = "Identifier of the storage container for GraphDB backups"
  value       = azurerm_storage_container.graphdb_backup.id
}

output "storage_container_name" {
  description = "Name of the storage container for GraphDB backups"
  value       = azurerm_storage_container.graphdb_backup.name
}
