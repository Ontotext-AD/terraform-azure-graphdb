# COMMON RESOURCES AND NETWORKING -------------------------------

locals {
  tags = merge({
    # Used to easily track all resource managed by Terraform
    Source     = "Terraform"
    Deployment = var.resource_name_prefix
  }, var.tags)
}

resource "azurerm_resource_group" "graphdb" {
  name     = var.resource_name_prefix
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
  name                = var.resource_name_prefix
  resource_group_name = azurerm_resource_group.graphdb.name
  location            = azurerm_resource_group.graphdb.location
  address_space       = var.virtual_network_address_space
}

resource "azurerm_subnet" "graphdb_gateway" {
  name                 = "${var.resource_name_prefix}-gateway"
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_name = azurerm_virtual_network.graphdb.name
  address_prefixes     = var.app_gateway_subnet_address_prefix
  service_endpoints    = ["Microsoft.KeyVault"]
}

resource "azurerm_subnet" "graphdb_vmss" {
  name                 = "${var.resource_name_prefix}-vmss"
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_name = azurerm_virtual_network.graphdb.name
  address_prefixes     = var.graphdb_subnet_address_prefix
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

resource "azurerm_network_security_group" "graphdb_gateway" {
  name                = "${var.resource_name_prefix}-gateway"
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
    destination_port_range      = 80
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
    destination_port_range      = 443
  }
}

resource "azurerm_network_security_group" "graphdb_vmss" {
  name                = "${var.resource_name_prefix}-vmss"
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

# Creates a public IP address with assigned FQDN from the regional Azure DNS
module "address" {
  source = "./modules/address"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name
  zones                = var.zones
}

# Creates a user assigned identity which will be provided to GraphDB VMs.
module "identity" {
  source = "./modules/identity"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name
}

# Creates Key Vault for secure storage of GraphDB configurations and secrets
module "vault" {
  source = "./modules/vault"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  nacl_subnet_ids = [azurerm_subnet.graphdb_gateway.id, azurerm_subnet.graphdb_vmss.id]
  nacl_ip_rules   = var.management_cidr_blocks

  key_vault_enable_purge_protection = var.key_vault_enable_purge_protection
  key_vault_retention_days          = var.key_vault_retention_days
}

# Creates a storage account for storing GraphDB backups
module "backup" {
  source = "./modules/backup"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  nacl_subnet_ids = [azurerm_subnet.graphdb_vmss.id]
  nacl_ip_rules   = var.management_cidr_blocks

  storage_account_tier             = var.storage_account_tier
  storage_account_replication_type = var.storage_account_replication_type
}

# Creates and assigns required roles to the identity and services
module "roles" {
  source = "./modules/roles"

  resource_name_prefix = var.resource_name_prefix
  resource_group_id    = azurerm_resource_group.graphdb.id

  identity_principal_id        = module.identity.identity_principal_id
  key_vault_id                 = module.vault.key_vault_id
  backups_storage_container_id = module.backup.storage_account_id
  private_dns_zone             = module.dns.private_dns_zone_id
}

# Managed GraphDB configurations in the Key Vault
module "configuration" {
  source = "./modules/configuration"

  key_vault_id          = module.vault.key_vault_id
  identity_principal_id = module.identity.identity_principal_id

  graphdb_password        = var.graphdb_password
  graphdb_license_path    = var.graphdb_license_path
  graphdb_cluster_token   = var.graphdb_cluster_token
  graphdb_properties_path = var.graphdb_properties_path
  graphdb_java_options    = var.graphdb_java_options

  # Wait for role assignments
  depends_on = [module.vault]
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

# Creates a public application gateway for forwarding internet traffic to the GraphDB proxies
module "application_gateway" {
  source = "./modules/gateway"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  gateway_subnet_id                 = azurerm_subnet.graphdb_gateway.id
  gateway_public_ip_id              = module.address.public_ip_address_id
  gateway_identity_id               = module.tls.tls_identity_id
  gateway_tls_certificate_secret_id = module.tls.tls_certificate_key_vault_secret_id

  # Wait for role assignments
  depends_on = [module.tls]
}

# Module for resolving the GraphDB shared image ID
module "graphdb_image" {
  source = "./modules/image"

  graphdb_version  = var.graphdb_version
  graphdb_image_id = var.graphdb_image_id
}

# Creates a bastion host for secure remote connections
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

module "user_data" {
  source = "./modules/user-data"

  count = var.custom_graphdb_vm_user_data != null ? 0 : 1

  graphdb_external_address_fqdn = module.address.public_ip_address_fqdn

  key_vault_name = module.vault.key_vault_name

  disk_iops_read_write = var.disk_iops_read_write
  disk_mbps_read_write = var.disk_mbps_read_write
  disk_size_gb         = var.disk_size_gb

  backup_storage_container_url = module.backup.storage_container_id
  backup_schedule              = var.backup_schedule
}

locals {
  user_data_script = var.custom_graphdb_vm_user_data != null ? var.custom_graphdb_vm_user_data : module.user_data[0].graphdb_vmss_user_data
}

# Creates a VM scale set for GraphDB and GraphDB cluster proxies
module "vmss" {
  source = "./modules/vmss"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name
  zones                = var.zones

  graphdb_subnet_id = azurerm_subnet.graphdb_vmss.id

  identity_id                                  = module.identity.identity_id
  application_gateway_backend_address_pool_ids = [module.application_gateway.gateway_backend_address_pool_id]

  instance_type = var.instance_type
  image_id      = module.graphdb_image.image_id
  node_count    = var.node_count
  ssh_key       = var.ssh_key

  user_data_script = local.user_data_script

  # Wait for configurations to be created in the key vault and roles to be assigned
  depends_on = [module.configuration, module.roles, module.dns]
}

module "dns" {
  source = "./modules/dns"

  resource_name_prefix = var.resource_name_prefix
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_id   = azurerm_virtual_network.graphdb.id

  depends_on = [
    module.identity
  ]
}
