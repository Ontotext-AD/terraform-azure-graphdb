provider "azurerm" {
  features {
    managed_disk {
      expand_without_downtime = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

locals {
  tags = merge({
    # Used to easily track all resource managed by Terraform
    Deployment = var.resource_name_prefix
    Source     = "Terraform"
  }, var.tags)
}

# ------------------------------------------------------------

# TODO: To be moved in another module

resource "azurerm_resource_group" "graphdb" {
  name     = var.resource_name_prefix
  location = var.location
  tags     = local.tags
}

resource "azurerm_management_lock" "graphdb-rg-lock" {
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
  tags                = local.tags
}

resource "azurerm_subnet" "graphdb-gateway" {
  name                 = "${var.resource_name_prefix}-gateway"
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_name = azurerm_virtual_network.graphdb.name
  address_prefixes     = var.app_gateway_subnet_address_prefix
}

resource "azurerm_subnet" "graphdb-vmss" {
  name                 = "${var.resource_name_prefix}-vmss"
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_name = azurerm_virtual_network.graphdb.name
  address_prefixes     = var.graphdb_subnet_address_prefix
}

# ------------------------------------------------------------

# Creates a public IP address with assigned FQDN from the regional Azure DNS
module "address" {
  source = "./modules/address"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name
  zones                = var.zones

  tags = local.tags
}

# Creates a user assigned identity which will be provided to GraphDB VMs.
module "identity" {
  source = "./modules/identity"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  tags = local.tags
}

# Creates Key Vault for secure storage of GraphDB configurations and secrets
module "vault" {
  source = "./modules/vault"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  tags = local.tags
}

# Managed GraphDB configurations in the Key Vault
module "configuration" {
  source = "./modules/configuration"

  key_vault_id          = module.vault.key_vault_id
  identity_principal_id = module.identity.identity_principal_id

  graphdb_license_path    = var.graphdb_license_path
  graphdb_cluster_token   = var.graphdb_cluster_token
  graphdb_properties_path = var.graphdb_properties_path
  graphdb_java_options    = var.graphdb_java_options

  tags = local.tags

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

  tags = local.tags

  # Wait for role assignments
  depends_on = [module.identity, module.vault]
}

# Creates a public application gateway for forwarding internet traffic to the GraphDB proxies
module "application_gateway" {
  source = "./modules/gateway"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name

  gateway_subnet_id                 = azurerm_subnet.graphdb-gateway.id
  gateway_public_ip_id              = module.address.public_ip_address_id
  gateway_identity_id               = module.tls.tls_identity_id
  gateway_tls_certificate_secret_id = module.tls.tls_certificate_key_vault_secret_id

  tags = local.tags

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

  resource_group_name           = azurerm_resource_group.graphdb.name
  location                      = var.location
  virtual_network_name          = azurerm_virtual_network.graphdb.name
  resource_name_prefix          = var.resource_name_prefix
  bastion_subnet_address_prefix = var.bastion_subnet_address_prefix

  tags = local.tags
}

# Creates a VM scale set for GraphDB and GraphDB cluster proxies
module "vm" {
  source = "./modules/vm"

  resource_name_prefix = var.resource_name_prefix
  location             = var.location
  resource_group_name  = azurerm_resource_group.graphdb.name
  resource_group_id    = azurerm_resource_group.graphdb.id
  zones                = var.zones

  graphdb_subnet_id   = azurerm_subnet.graphdb-vmss.id
  graphdb_subnet_cidr = one(azurerm_subnet.graphdb-vmss.address_prefixes)

  identity_id                                  = module.identity.identity_id
  identity_principal_id                        = module.identity.identity_principal_id
  application_gateway_backend_address_pool_ids = [module.application_gateway.gateway_backend_address_pool_id]

  # Configurations for the user data script
  graphdb_external_address_fqdn = module.address.public_ip_address_fqdn
  key_vault_name                = module.vault.key_vault_name

  disk_iops_read_write = var.disk_iops_read_write
  disk_mbps_read_write = var.disk_mbps_read_write
  disk_size_gb         = var.disk_size_gb

  instance_type     = var.instance_type
  image_id          = module.graphdb_image.image_id
  node_count        = var.node_count
  ssh_key           = var.ssh_key
  source_ssh_blocks = var.source_ssh_blocks

  custom_user_data = var.custom_graphdb_vm_user_data

  tags = local.tags

  # Wait for configurations to be created in the key vault and roles to be assigned
  depends_on = [module.configuration]
}
