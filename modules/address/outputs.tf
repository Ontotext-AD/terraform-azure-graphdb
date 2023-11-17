output "public_ip_address_name" {
  description = "Name of the public IP address"
  value       = azurerm_public_ip.graphdb-public-ip-address.name
}

output "public_ip_address_fqdn" {
  description = "The assigned FQDN of the public IP address"
  value       = azurerm_public_ip.graphdb-public-ip-address.fqdn
}
