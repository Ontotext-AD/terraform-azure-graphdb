output "public_address" {
  description = "Public address for GraphDB"
  value       = "https://${module.application_gateway.public_ip_address_fqdn}"
}

output "public_ip_address" {
  description = "The public IP address of the application gateway"
  value       = module.application_gateway.public_ip_address
}
