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
  value       = azurerm_application_gateway.graphdb.id
}

output "gateway_backend_address_pool_id" {
  description = "Identifier of the application gateway backend address pool"
  value       = one(azurerm_application_gateway.graphdb.backend_address_pool).id
}
