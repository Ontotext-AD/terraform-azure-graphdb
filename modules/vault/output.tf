output "key_vault_name" {
  description = "Key vault name for storing GraphDB configurations and secrets"
  value       = azurerm_key_vault.graphdb.name
}
