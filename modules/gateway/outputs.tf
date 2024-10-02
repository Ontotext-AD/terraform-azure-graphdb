# Public IP

output "public_ip_address_name" {
  description = "Name of the public IP address"
  value       = azurerm_public_ip.graphdb_public_ip_address.name
}

output "public_ip_address" {
  description = "The public IPv4 address"
  value       = azurerm_public_ip.graphdb_public_ip_address.ip_address
}

output "public_ip_address_id" {
  description = "Identifier of the public IP address"
  value       = azurerm_public_ip.graphdb_public_ip_address.id
}

output "public_ip_address_fqdn" {
  description = "The assigned FQDN of the public IP address"
  value       = azurerm_public_ip.graphdb_public_ip_address.fqdn
}

# Gateway

output "gateway_id" {
  description = "Identifier of the application gateway for GraphDB"
  value       = var.gateway_enable_private_access && length(azurerm_application_gateway.graphdb-private) > 0 ? azurerm_application_gateway.graphdb-private[0].id : !var.gateway_enable_private_access && length(azurerm_application_gateway.graphdb-public) > 0 ? azurerm_application_gateway.graphdb-public[0].id : null
}

output "gateway_backend_address_pool_id" {
  description = "Identifier of the application gateway backend address pool"
  value = (var.gateway_enable_private_access && length(azurerm_application_gateway.graphdb-private) > 0 && length(azurerm_application_gateway.graphdb-private[0].backend_address_pool) > 0
    ? one(azurerm_application_gateway.graphdb-private[0].backend_address_pool).id
    : !var.gateway_enable_private_access && length(azurerm_application_gateway.graphdb-public) > 0 && length(azurerm_application_gateway.graphdb-public[0].backend_address_pool) > 0
    ? one(azurerm_application_gateway.graphdb-public[0].backend_address_pool).id
  : null)
}

