output "public_address" {
  description = "Public address for GraphDB"
  value = var.disable_agw ? (
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
}

