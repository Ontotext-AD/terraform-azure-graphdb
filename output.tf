output "public_address_fqdn" {
  description = "External FQDN address for GraphDB"
  value       = module.address.public_ip_address_fqdn
}
