output "public_ip_address" {
  description = "Public IP address of the Jump VM"
  value       = azurerm_public_ip.jumpvm.ip_address
}

output "private_ip_address" {
  description = "Private IP address of the Jump VM"
  value       = azurerm_network_interface.jumpvm.private_ip_address
}

output "subnet_address_prefixes" {
  description = "Address prefixes of the Jump VM subnet"
  value       = azurerm_subnet.jumpvm.address_prefixes
}