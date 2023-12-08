output "app_configuration_id" {
  description = "Identifier of the App Configuration store for GraphDB"
  value       = azurerm_app_configuration.graphdb.id
}

output "app_configuration_name" {
  description = "Name of the App Configuration store for GraphDB"
  value       = azurerm_app_configuration.graphdb.name
}
