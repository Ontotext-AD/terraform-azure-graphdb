output "public_address" {
  description = "Public address for GraphDB"
  value = var.gateway_enable_private_access ? null : (
    var.disable_agw ? (
      # If disable_agw is true, use graphdb_external_address_fqdn with context_path if set
      "https://${coalesce(var.graphdb_external_address_fqdn, "")}${length(var.context_path) > 0 ? "/${trim(var.context_path, "/")}" : ""}/"
      ) : (
      # If disable_agw is false, check context_path
      length(var.context_path) > 0 ?
      # If context_path has content, use application_gateway with context_path
      "https://${module.application_gateway[0].public_ip_address_fqdn}/${trim(var.context_path, "/")}/" :
      # If context_path is empty, use application_gateway without path
      "https://${module.application_gateway[0].public_ip_address_fqdn}/"
    )
  )
}

output "private_ip_address" {
  description = "The Private IPv4 address for accessing GraphDB via the Application Gateway"
  value       = var.gateway_enable_private_access ? module.application_gateway[0].private_ip_address : null
}

output "public_ip_address_id" {
  description = "The ID of the Public IP Address associated with the Application Gateway"
  value = (var.disable_agw || var.gateway_enable_private_access) ? null : module.application_gateway[0].public_ip_address_id
}

output "public_ip_address" {
  description = "The Public IP address for accessing GraphDB via the Application Gateway"
  value       = (var.disable_agw || var.gateway_enable_private_access) ? null : module.application_gateway[0].public_ip_address
}

output "application_gateway_fqdn" {
  description = "The FQDN of the Application Gateway"
  value       = (var.disable_agw) ? null : module.application_gateway[0].public_ip_address_fqdn
}

