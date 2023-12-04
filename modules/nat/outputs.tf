output "nat_public_ip_address" {
  description = "The public IPv4 address for the NAT gateway"
  value       = azurerm_public_ip.graphdb_nat_ip_address.ip_address
}

output "nat_public_ip_address_id" {
  description = "Identifier of the public IP address for the NAT gateway"
  value       = azurerm_public_ip.graphdb_nat_ip_address.id
}
