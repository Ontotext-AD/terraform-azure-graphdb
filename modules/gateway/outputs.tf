output "gateway_id" {
  description = "Identifier of the application gateway for GraphDB"
  value       = azurerm_application_gateway.graphdb.id
}

output "gateway_backend_address_pool_id" {
  description = "Identifier of the application gateway backend address pool"
  value       = one(azurerm_application_gateway.graphdb.backend_address_pool).id
}
