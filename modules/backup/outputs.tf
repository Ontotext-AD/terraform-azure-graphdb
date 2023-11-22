output "storage_account_name" {
  description = "Storage account name for storing GraphDB backups"
  value       = azurerm_storage_account.backup.name
}

output "container_name" {
  value = azurerm_storage_container.backup.name
}
