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

output "resource_group_name" {
  description = "Resource group where the zone resides."
  value       = local.rg_name
}

output "a_records" {
  description = "Map of A records created in the zone."
  value       = var.private_zone ? [for r in azurerm_private_dns_a_record.a_private : r.fqdn] : [for r in azurerm_dns_a_record.a_public : r.fqdn]

}

output "cname_records" {
  description = "Map of CNAME records created in the zone."
  value       = var.private_zone ? [for r in azurerm_private_dns_cname_record.cname_private : r.fqdn] : [for r in azurerm_dns_cname_record.cname_public : r.fqdn]
}

output "mx_records" {
  description = "Map of MX records created in the zone."
  value       = var.private_zone ? azurerm_private_dns_mx_record.mx_private : azurerm_dns_mx_record.mx_public
}

output "txt_records" {
  description = "Map of TXT records created in the zone."
  value       = var.private_zone ? azurerm_private_dns_txt_record.txt_private : azurerm_dns_txt_record.txt_public
}

output "ns_records" {
  description = "Map of NS records created in the zone."
  value       = var.private_zone ? {} : azurerm_dns_ns_record.ns_public
}

output "srv_records" {
  description = "Map of SRV records created in the zone."
  value       = var.private_zone ? azurerm_private_dns_srv_record.srv_private : azurerm_dns_srv_record.srv_public
}
