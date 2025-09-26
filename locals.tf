locals {
  tags = merge({
    # Used to easily track all resource managed by Terraform
    Source     = "Terraform"
    Deployment = var.resource_name_prefix
    CreatedBy  = data.azurerm_client_config.current.object_id
    CreatedOn  = time_static.current.rfc3339
  }, var.tags)
  admin_security_principle_id = var.admin_security_principle_id != null ? var.admin_security_principle_id : data.azurerm_client_config.current.object_id

  static_keys = {
    vnet                       = "virtual_network"
    application_gateway_subnet = "gateway_subnet"
    subnets                    = "vmss_subnet"
    backup                     = "backup_storage"
    monitoring                 = "monitoring_workspace"
    appconfig                  = "app_configuration"
    application_gateway        = "application_gateway"
    vault                      = "key_vault"
    vmss                       = "vmss"
  }

  resources_to_lock = {
    "vnet"                       = azurerm_virtual_network.graphdb[0].id
    "application_gateway_subnet" = azurerm_subnet.graphdb_gateway.id
    "subnets"                    = azurerm_subnet.graphdb_vmss.id
    "backup"                     = module.backup.storage_account_id
    "monitoring"                 = var.deploy_monitoring ? module.monitoring[0].la_workspace_id : null
    "appconfig"                  = module.appconfig.app_configuration_id
    "application_gateway"        = var.disable_agw ? null : module.application_gateway[0].gateway_id
    "vault"                      = var.tls_certificate_id == null ? module.vault[0].key_vault_id : null
    "vmss"                       = module.graphdb.vmss_resource_id
  }

  resources_to_lock_filtered = {
    for key, value in local.static_keys :
    key => try(local.resources_to_lock[key], null)
    if(key != "monitoring" || var.deploy_monitoring) &&
    (key != "application_gateway" && key != "application_gateway_subnet" || !var.disable_agw) &&
    value != null && value != ""
  }

  _rec_name = trimspace(var.external_dns_record_name) == "" ? "@" : var.external_dns_record_name

  _cname_label = local._rec_name == "@" ? "www" : "www.${local._rec_name}"

  has_appgw = !var.disable_agw

  a_records_list_effective = (
    length(var.external_dns_records_a_records_list) > 0 ? var.external_dns_records_a_records_list :
    local.has_appgw ? [
      {
        name               = local._rec_name
        ttl                = var.external_dns_record_ttl
        records            = null
        target_resource_id = try(module.application_gateway[0].public_ip_address_id, null)
      }
    ] : []
  )

  cname_records_list_effective = (
    length(var.external_dns_records_cname_records_list) > 0 ? var.external_dns_records_cname_records_list :
    local.has_appgw ? [
      {
        name               = local._cname_label
        ttl                = var.external_dns_record_ttl
        record             = try(module.application_gateway[0].public_ip_address_fqdn, null)
        target_resource_id = null
      }
    ] : []
  )
}
