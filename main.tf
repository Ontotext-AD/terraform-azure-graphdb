# COMMON RESOURCES AND NETWORKING -------------------------------

data "azurerm_client_config" "current" {}

resource "time_static" "current" {}

locals {
  tags = merge({
    # Used to easily track all resource managed by Terraform
    Source     = "Terraform"
    Deployment = var.resource_name_prefix
    CreatedBy  = data.azurerm_client_config.current.object_id
    CreatedOn  = time_static.current.rfc3339
  }, var.tags)
  admin_security_principle_id = var.admin_security_principle_id != null ? var.admin_security_principle_id : data.azurerm_client_config.current.object_id
}

resource "azurerm_resource_group" "graphdb" {
  count    = var.resource_group_name == null ? 1 : 0
  name     = "rg-${var.resource_name_prefix}"
  location = var.location
  tags     = local.tags

  lifecycle {
    # Ignore remote changes to the resource group's tags
    ignore_changes = [tags]
  }
}

data "azurerm_resource_group" "existing_graphdb_rg" {
  count = var.resource_group_name == null ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group_id   = var.resource_group_name != null ? data.azurerm_resource_group.existing_graphdb_rg[0].id : azurerm_resource_group.graphdb[0].id
  resource_group_name = var.resource_group_name != null ? data.azurerm_resource_group.existing_graphdb_rg[0].name : azurerm_resource_group.graphdb[0].name
}

resource "azurerm_management_lock" "graphdb_rg_lock" {
  count      = var.lock_resources ? 1 : 0
  name       = "${var.resource_name_prefix}-rg-lock"
  scope      = local.resource_group_id
  lock_level = "CanNotDelete"
  notes      = "Prevents from deleting the resource group"
}

resource "azurerm_virtual_network" "graphdb" {
  count = var.virtual_network_name == null ? 1 : 0

  name                = "vnet-${var.resource_name_prefix}"
  resource_group_name = local.resource_group_name
  location            = var.location
  address_space       = var.virtual_network_address_space
}

data "azurerm_virtual_network" "existing_vnet" {
  count = var.virtual_network_name == null ? 0 : 1

  name                = var.virtual_network_name
  resource_group_name = local.resource_group_name
}

locals {
  virtual_network_id   = var.virtual_network_name != null ? data.azurerm_virtual_network.existing_vnet[0].id : azurerm_virtual_network.graphdb[0].id
  virtual_network_name = var.virtual_network_name != null ? data.azurerm_virtual_network.existing_vnet[0].name : azurerm_virtual_network.graphdb[0].name
}

resource "azurerm_subnet" "graphdb_gateway" {
  name                 = "snet-${var.resource_name_prefix}-gateway"
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.virtual_network_name
  address_prefixes     = var.gateway_subnet_address_prefixes
  service_endpoints    = ["Microsoft.KeyVault"]
}

resource "azurerm_subnet" "graphdb_vmss" {
  name                 = "snet-${var.resource_name_prefix}-vmss"
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.virtual_network_name
  address_prefixes     = var.graphdb_subnet_address_prefixes
  service_endpoints    = ["Microsoft.Storage"]
}

# SUB MODULES ------------------------------------------------------------

# Creates Key Vault for storing a provided TLS certificate file
module "vault" {
  count = var.tls_certificate_id == null ? 1 : 0

  source = "./modules/vault"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = local.resource_group_name

  nacl_subnet_ids = [azurerm_subnet.graphdb_gateway.id]
  nacl_ip_rules   = var.management_cidr_blocks

  key_vault_enable_purge_protection    = var.key_vault_enable_purge_protection
  key_vault_soft_delete_retention_days = var.key_vault_soft_delete_retention_days

  admin_security_principle_id = local.admin_security_principle_id
}

# Creates a Storage Account for storing GraphDB backups
module "backup" {
  source = "./modules/backup"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = local.resource_group_name

  nacl_subnet_ids = [azurerm_subnet.graphdb_vmss.id]
  nacl_ip_rules   = var.management_cidr_blocks

  storage_account_tier                  = var.storage_account_tier
  storage_account_replication_type      = var.storage_account_replication_type
  storage_blobs_max_days_since_creation = var.storage_blobs_max_days_since_creation
  storage_account_retention_hot_to_cool = var.storage_account_retention_hot_to_cool

  storage_container_soft_delete_retention_policy = var.storage_container_soft_delete_retention_policy
  storage_blob_soft_delete_retention_policy      = var.storage_blob_soft_delete_retention_policy
}

# Creates an App Configuration store for managing GraphDB specific configurations
module "appconfig" {
  source = "./modules/appconfig"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = local.resource_group_name

  app_config_enable_purge_protection    = var.app_config_enable_purge_protection
  app_config_soft_delete_retention_days = var.app_config_soft_delete_retention_days

  admin_security_principle_id = local.admin_security_principle_id
}

# Creates a TLS certificate secret in the Key Vault and related identity (if file is provided)
module "tls" {
  count = var.tls_certificate_id == null ? 1 : 0

  source = "./modules/tls"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = local.resource_group_name

  key_vault_id             = module.vault[0].key_vault_id
  tls_certificate          = filebase64(var.tls_certificate_path)
  tls_certificate_password = var.tls_certificate_password

  # Wait for role assignments
  depends_on = [module.vault[0]]
}

# Creates a public IP address and an Application Gateway for forwarding internet traffic to the GraphDB proxies/instances
module "application_gateway" {
  source = "./modules/gateway"

  count = var.disable_agw ? 0 : 1

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = local.resource_group_name
  zones                = var.zones
  node_count           = var.node_count

  virtual_network_name             = local.virtual_network_name
  gateway_subnet_id                = azurerm_subnet.graphdb_gateway.id
  gateway_subnet_address_prefixes  = azurerm_subnet.graphdb_gateway.address_prefixes
  gateway_allowed_address_prefix   = var.inbound_allowed_address_prefix
  gateway_allowed_address_prefixes = var.inbound_allowed_address_prefixes

  # Health probe settings
  gateway_probe_interval  = var.gateway_probe_interval
  gateway_probe_timeout   = var.gateway_probe_timeout
  gateway_probe_threshold = var.gateway_probe_threshold

  # Public / Private toggle
  gateway_enable_private_access = var.gateway_enable_private_access

  disable_agw  = var.disable_agw
  context_path = var.context_path

  # TLS
  gateway_tls_certificate_secret_id   = var.tls_certificate_id != null ? var.tls_certificate_id : module.tls[0].tls_certificate_id
  gateway_tls_certificate_identity_id = var.tls_certificate_id != null ? var.tls_certificate_identity_id : module.tls[0].tls_identity_id

  # Private Link
  gateway_enable_private_link_service                   = var.gateway_enable_private_link_service
  gateway_private_link_subnet_address_prefixes          = var.gateway_private_link_subnet_address_prefixes
  gateway_private_link_service_network_policies_enabled = var.gateway_private_link_service_network_policies_enabled

  # Global buffer settings
  gateway_global_request_buffering_enabled  = var.gateway_global_request_buffering_enabled
  gateway_global_response_buffering_enabled = var.gateway_global_response_buffering_enabled

  # Wait for role assignments
  depends_on = [module.tls]
}

# Creates an Azure Bastion host for secure remote connections
module "bastion" {
  count = var.deploy_bastion ? 1 : 0

  source = "./modules/bastion"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = local.resource_group_name

  virtual_network_name                     = local.virtual_network_name
  bastion_subnet_address_prefixes          = var.bastion_subnet_address_prefixes
  bastion_allowed_inbound_address_prefixes = var.management_cidr_blocks
}

# Configures Azure monitoring
module "monitoring" {
  count = var.deploy_monitoring ? 1 : 0

  source = "./modules/monitoring"

  resource_name_prefix = var.resource_name_prefix
  resource_group_name  = local.resource_group_name
  location             = var.location
  node_count           = var.node_count

  web_test_availability_request_url = var.disable_agw ? var.graphdb_external_address_fqdn : module.application_gateway[0].public_ip_address_fqdn
  web_test_geo_locations            = var.web_test_geo_locations
  web_test_ssl_check_enabled        = var.web_test_ssl_check_enabled

  graphdb_external_address_fqdn = var.graphdb_external_address_fqdn != null ? var.graphdb_external_address_fqdn : module.application_gateway[0].public_ip_address_fqdn

  monitor_reader_principal_id = var.monitor_reader_principal_id

  appi_disable_ip_masking                    = var.appi_disable_ip_masking
  appi_web_test_availability_enabled         = var.appi_web_test_availability_enabled
  appi_daily_data_cap_notifications_disabled = var.appi_daily_data_cap_notifications_disabled
  appi_daily_data_cap_in_gb                  = var.appi_daily_data_cap_in_gb
  appi_retention_in_days                     = var.appi_retention_in_days

  la_workspace_sku               = var.la_workspace_sku
  la_workspace_retention_in_days = var.la_workspace_retention_in_days

  ag_notifications_email_list = var.notification_recipients_email_list

  # Diagnostic settings
  app_configuration_id                 = module.appconfig.app_configuration_id
  key_vault_id                         = var.tls_certificate_id != null ? null : module.vault[0].key_vault_id
  create_key_vault_diagnostic_settings = var.tls_certificate_id == null ? true : false
}

locals {
  # If node_count is 1 take the first zone only, if node_count > 1 use all provided zones.
  adjusted_zones = var.node_count == 1 ? [element(var.zones, 0)] : var.zones
}

# Creates a VM scale set for GraphDB and GraphDB cluster proxies
module "graphdb" {
  source = "./modules/graphdb"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_id    = local.resource_group_id
  resource_group_name  = local.resource_group_name
  zones                = local.adjusted_zones

  # Networking
  virtual_network_id                   = local.virtual_network_id
  graphdb_subnet_id                    = azurerm_subnet.graphdb_vmss.id
  graphdb_inbound_address_prefixes     = var.gateway_subnet_address_prefixes
  graphdb_ssh_inbound_address_prefixes = var.deploy_bastion ? var.bastion_subnet_address_prefixes : []
  graphdb_outbound_address_prefix      = var.outbound_allowed_address_prefix
  graphdb_outbound_address_prefixes    = var.outbound_allowed_address_prefixes

  # Gateway
  application_gateway_backend_address_pool_ids = var.disable_agw ? [] : [module.application_gateway[0].gateway_backend_address_pool_id]

  context_path = var.context_path

  # App Configuration
  app_configuration_id       = module.appconfig.app_configuration_id
  app_configuration_endpoint = module.appconfig.app_configuration_endpoint

  # GraphDB Configurations
  graphdb_external_address_fqdn = var.graphdb_external_address_fqdn != null ? var.graphdb_external_address_fqdn : (var.disable_agw ? null : module.application_gateway[0].public_ip_address_fqdn)
  graphdb_password              = var.graphdb_password
  graphdb_license_path          = var.graphdb_license_path
  graphdb_cluster_token         = var.graphdb_cluster_token
  graphdb_properties_path       = var.graphdb_properties_path
  graphdb_java_options          = var.graphdb_java_options

  # Backups Storage Account
  backup_storage_account_name   = module.backup.storage_account_name
  backup_storage_container_id   = module.backup.storage_account_id
  backup_storage_container_name = module.backup.storage_container_name
  backup_schedule               = var.backup_schedule

  # VM Image
  graphdb_sku      = var.graphdb_sku
  graphdb_version  = var.graphdb_version
  graphdb_image_id = var.graphdb_image_id

  # VMSS
  instance_type         = var.instance_type
  node_count            = var.node_count
  ssh_key               = var.ssh_key
  user_supplied_scripts = var.user_supplied_scripts
  vmss_dns_servers      = var.vmss_dns_servers

  # Managed Disks
  disk_iops_read_write       = var.disk_iops_read_write
  disk_mbps_read_write       = var.disk_mbps_read_write
  disk_size_gb               = var.disk_size_gb
  disk_network_access_policy = var.disk_network_access_policy
  disk_public_network_access = var.disk_public_network_access
  disk_storage_account_type  = var.disk_storage_account_type

  # Scale set actions notifications
  scaleset_actions_recipients_email_list = var.notification_recipients_email_list

  # App Insights
  appi_connection_string = var.deploy_monitoring ? module.monitoring[0].appi_connection_string : ""

  # Wait for the configurations to be created in the App Configuration store
  disable_agw = var.disable_agw

  depends_on = [module.appconfig]
}
