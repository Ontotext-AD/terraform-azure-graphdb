output "storage_account_name" {
  value = azurerm_storage_account.backup.name
}

output "container_name" {
  value = azurerm_storage_container.backup.name
}