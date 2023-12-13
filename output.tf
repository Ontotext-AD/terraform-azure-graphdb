output "public_address_fqdn" {
  description = "External FQDN address for GraphDB"
  value       = module.application_gateway.public_ip_address_fqdn
}
