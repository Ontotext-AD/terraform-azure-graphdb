output "private_dns_zone_id" {
  description = "ID of the private DNS zone for Azure DNS resolving"
  value       = azurerm_private_dns_zone.zone.id
}
