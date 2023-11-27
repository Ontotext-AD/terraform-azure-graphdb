output "storage_account_name" {
  description = "Storage account name for storing GraphDB backups"
  value       = azurerm_storage_account.graphdb-backup.name
}

output "container_name" {
  description = "Name of the storage container for GraphDB backups"
  value       = azurerm_storage_container.graphdb-backup.name
}
