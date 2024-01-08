# COMMON RESOURCES AND NETWORKING -------------------------------

locals {
  tags = merge({
    # Used to easily track all resource managed by Terraform
    Source     = "Terraform"
    Deployment = var.resource_name_prefix
  }, var.tags)
}

resource "azurerm_resource_group" "graphdb" {
  name     = "rg-${var.resource_name_prefix}"
  location = var.location
  tags     = local.tags

  lifecycle {
    # Ignore remote changes to the resource group's tags
    ignore_changes = [tags]
  }
}

resource "azurerm_management_lock" "graphdb_rg_lock" {
  count      = var.lock_resources ? 1 : 0
  name       = "${var.resource_name_prefix}-rg"
  scope      = azurerm_resource_group.graphdb.id
  lock_level = "CanNotDelete"
  notes      = "Prevents deleting the resource group"
}

resource "azurerm_virtual_network" "graphdb" {
  name                = "vnet-${var.resource_name_prefix}"
  resource_group_name = azurerm_resource_group.graphdb.name
  location            = azurerm_resource_group.graphdb.location
  address_space       = var.virtual_network_address_space
}

resource "azurerm_subnet" "graphdb_gateway" {
  name                 = "snet-${var.resource_name_prefix}-gateway"
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_name = azurerm_virtual_network.graphdb.name
  address_prefixes     = var.app_gateway_subnet_address_prefix
  service_endpoints    = ["Microsoft.KeyVault"]
}

resource "azurerm_subnet" "graphdb_vmss" {
  name                 = "snet-${var.resource_name_prefix}-vmss"
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_name = azurerm_virtual_network.graphdb.name
  address_prefixes     = var.graphdb_subnet_address_prefix
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

resource "azurerm_network_security_group" "graphdb_gateway" {
  name                = "nsg-${var.resource_name_prefix}-gateway"
  resource_group_name = azurerm_resource_group.graphdb.name
  location            = var.location

  security_rule {
    name                       = "AllowGatewayManager"
    description                = "Allows Gateway Manager to perform health monitoring."
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "GatewayManager"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "65200-65535"
  }

  security_rule {
    name                         = "AllowInternetInboundHttp"
    description                  = "Allows HTTP inbound internet traffic to the gateway subnet."
    priority                     = 200
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_address_prefix        = "Internet"
    source_port_range            = "*"
    destination_address_prefixes = var.app_gateway_subnet_address_prefix
    destination_port_range       = 80
  }

  security_rule {
    name                         = "AllowInternetInboundHttps"
    description                  = "Allows HTTPS inbound internet traffic to the gateway subnet."
    priority                     = 210
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_address_prefix        = "Internet"
    source_port_range            = "*"
    destination_address_prefixes = var.app_gateway_subnet_address_prefix
    destination_port_range       = 443
  }
}

resource "azurerm_network_security_group" "graphdb_vmss" {
  name                = "nsg-${var.resource_name_prefix}-vmss"
  resource_group_name = azurerm_resource_group.graphdb.name
  location            = var.location
}

resource "azurerm_subnet_network_security_group_association" "graphdb_gateway" {
  network_security_group_id = azurerm_network_security_group.graphdb_gateway.id
  subnet_id                 = azurerm_subnet.graphdb_gateway.id
}

resource "azurerm_subnet_network_security_group_association" "graphdb_vmss" {
  network_security_group_id = azurerm_network_security_group.graphdb_vmss.id
  subnet_id                 = azurerm_subnet.graphdb_vmss.id
}

# SUB MODULES ------------------------------------------------------------

# Creates Key Vault for secure storage of GraphDB configurations and secrets
module "vault" {
  source = "./modules/vault"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  nacl_subnet_ids = [azurerm_subnet.graphdb_gateway.id]
  nacl_ip_rules   = var.management_cidr_blocks

  key_vault_enable_purge_protection = var.key_vault_enable_purge_protection
  key_vault_retention_days          = var.key_vault_retention_days

  assign_administrator_role = var.assign_data_owner_roles
  storage_account_id        = module.backup.storage_account_id
}

# Creates a Storage Account for storing GraphDB backups
module "backup" {
  source = "./modules/backup"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  nacl_subnet_ids = [azurerm_subnet.graphdb_vmss.id]
  nacl_ip_rules   = var.management_cidr_blocks

  storage_account_tier                  = var.storage_account_tier
  storage_account_replication_type      = var.storage_account_replication_type
  storage_account_retention_hot_to_cool = var.storage_account_retention_hot_to_cool
}

# Creates a Private DNS zone for GraphDB internal cluster communication
module "dns" {
  source = "./modules/dns"

  resource_name_prefix = var.resource_name_prefix
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_id   = azurerm_virtual_network.graphdb.id
}

# Creates an App Configuration store for managing GraphDB specific configurations
module "appconfig" {
  source = "./modules/appconfig"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  app_config_enable_purge_protection = var.app_config_enable_purge_protection
  app_config_retention_days          = var.app_config_retention_days

  assign_owner_role = var.assign_data_owner_roles
}

# Creates GraphDB configuration key values in the App Configuration store
module "configurations" {
  source = "./modules/configurations"

  app_configuration_id = module.appconfig.app_configuration_id

  graphdb_password        = var.graphdb_password
  graphdb_license_path    = var.graphdb_license_path
  graphdb_cluster_token   = var.graphdb_cluster_token
  graphdb_properties_path = var.graphdb_properties_path
  graphdb_java_options    = var.graphdb_java_options

  # Wait for role assignments
  depends_on = [module.appconfig]
}

# Creates a TLS certificate secret in the Key Vault and related identity
module "tls" {
  source = "./modules/tls"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  key_vault_id             = module.vault.key_vault_id
  tls_certificate          = filebase64(var.tls_certificate_path)
  tls_certificate_password = var.tls_certificate_password

  # Wait for role assignments
  depends_on = [module.vault]
}

# Creates a public IP address and an Application Gateway for forwarding internet traffic to the GraphDB proxies/instances
module "application_gateway" {
  source = "./modules/gateway"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name
  zones                = var.zones

  gateway_subnet_id = azurerm_subnet.graphdb_gateway.id

  gateway_tls_identity_id           = module.tls.tls_identity_id
  gateway_tls_certificate_secret_id = module.tls.tls_certificate_key_vault_secret_id

  # Wait for role assignments
  depends_on = [module.tls]
}

# Creates an Azure Bastion host for secure remote connections
module "bastion" {
  count = var.deploy_bastion ? 1 : 0

  source = "./modules/bastion"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  virtual_network_name          = azurerm_virtual_network.graphdb.name
  bastion_subnet_address_prefix = var.bastion_subnet_address_prefix
  bastion_allowed_cidr_blocks   = var.management_cidr_blocks
}

# Creates a NAT gateway associated with GraphDB's subnet
module "nat" {
  source = "./modules/nat"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name
  zones                = var.zones

  nat_subnet_id = azurerm_subnet.graphdb_vmss.id
}

# Prepares a user data script for GraphDB VMSS
module "user_data" {
  source = "./modules/user-data"

  count = var.custom_graphdb_vm_user_data != null ? 0 : 1

  graphdb_external_address_fqdn = module.application_gateway.public_ip_address_fqdn

  app_configuration_name = module.appconfig.app_configuration_name

  disk_iops_read_write = var.disk_iops_read_write
  disk_mbps_read_write = var.disk_mbps_read_write
  disk_size_gb         = var.disk_size_gb

  backup_storage_container_url = module.backup.storage_container_id
  backup_schedule              = var.backup_schedule
}

locals {
  user_data_script         = var.custom_graphdb_vm_user_data != null ? var.custom_graphdb_vm_user_data : module.user_data[0].graphdb_vmss_user_data
  graphdb_gallery_image_id = "/communityGalleries/${var.graphdb_image_gallery}/images/${var.graphdb_version}-${var.graphdb_image_architecture}/versions/${var.graphdb_image_version}"
  graphdb_image_id         = var.graphdb_image_id != null ? var.graphdb_image_id : local.graphdb_gallery_image_id
}

# Creates a VM scale set for GraphDB and GraphDB cluster proxies
module "vmss" {
  source = "./modules/vmss"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_id    = azurerm_resource_group.graphdb.id
  resource_group_name  = azurerm_resource_group.graphdb.name
  zones                = var.zones

  graphdb_subnet_id                            = azurerm_subnet.graphdb_vmss.id
  application_gateway_backend_address_pool_ids = [module.application_gateway.gateway_backend_address_pool_id]

  key_vault_id                 = module.vault.key_vault_id
  app_configuration_id         = module.appconfig.app_configuration_id
  backups_storage_container_id = module.backup.storage_account_id
  private_dns_zone             = module.dns.private_dns_zone_id

  instance_type = var.instance_type
  image_id      = local.graphdb_image_id
  node_count    = var.node_count
  ssh_key       = var.ssh_key

  user_data_script = local.user_data_script

  # Wait for the configurations to be created in the App Configuration store
  depends_on = [module.configurations]
}
