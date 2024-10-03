output "public_address" {
  description = "Public address for GraphDB"
  value       = var.disable_agw ? null : "https://${module.application_gateway[0].public_ip_address_fqdn}"
}

output "public_ip_address" {
  description = "The public IP address of the application gateway"
  value       = var.disable_agw ? null : module.application_gateway[0].public_ip_address
}