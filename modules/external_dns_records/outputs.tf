output "zone_id" {
  description = "Azure resource ID of the DNS zone."
  value       = var.private_zone ? azurerm_private_dns_zone.private[0].id : azurerm_dns_zone.public[0].id
}

output "zone_name" {
  description = "DNS zone name."
  value       = var.private_zone ? azurerm_private_dns_zone.private[0].name : azurerm_dns_zone.public[0].name
}

output "name_servers" {
  description = "Authoritative name servers (public zones only)."
  value       = var.private_zone ? null : azurerm_dns_zone.public[0].name_servers
}

output "a_records" {
  description = "Map of A records created in the zone."
  value       = var.private_zone ? [for r in azurerm_private_dns_a_record.a_private : r.fqdn] : [for r in azurerm_dns_a_record.a_public : r.fqdn]

}

output "cname_records" {
  description = "Map of CNAME records created in the zone."
  value       = var.private_zone ? [for r in azurerm_private_dns_cname_record.cname_private : r.fqdn] : [for r in azurerm_dns_cname_record.cname_public : r.fqdn]
}
