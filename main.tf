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

resource "azurerm_subnet" "graphdb-vmss" {
  name                 = "${var.resource_name_prefix}-vmss"
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_name = azurerm_virtual_network.graphdb.name
  address_prefixes     = var.graphdb_subnet_address_prefix
}

# ------------------------------------------------------------

# Creates a user assigned identity which will be provided to GraphDB VMs.
module "identity" {
  source = "./modules/identity"

  resource_name_prefix = var.resource_name_prefix
  resource_group_name  = azurerm_resource_group.graphdb.name

  tags = local.tags

  depends_on = [azurerm_resource_group.graphdb]
}

# Creates Key Vault for secure storage of GraphDB configurations and secrets
module "vault" {
  source = "./modules/vault"

  resource_name_prefix = var.resource_name_prefix
  resource_group_name  = azurerm_resource_group.graphdb.name

  tags = local.tags

  depends_on = [azurerm_resource_group.graphdb]
}

# Managed GraphDB configurations in the Key Vault
module "configuration" {
  source = "./modules/configuration"

  resource_group_name = azurerm_resource_group.graphdb.name

  identity_name        = module.identity.identity_name
  graphdb_license_path = var.graphdb_license_path
  key_vault_name       = module.vault.key_vault_name

  tags = local.tags

  depends_on = [
    azurerm_resource_group.graphdb,
    # Wait for complete module creation
    module.vault
  ]
}

# Creates a public load balancer for forwarding internet traffic to the GraphDB proxies
module "load_balancer" {
  source = "./modules/load_balancer"

  resource_name_prefix = var.resource_name_prefix
  resource_group_name  = azurerm_resource_group.graphdb.name

  tags = local.tags

  depends_on = [azurerm_resource_group.graphdb, azurerm_virtual_network.graphdb]
}

# Module for resolving the GraphDB shared image ID
module "graphdb_image" {
  source = "./modules/image"

  graphdb_version  = var.graphdb_version
  graphdb_image_id = var.graphdb_image_id
}

# Creates a VM scale set for GraphDB and GraphDB cluster proxies
module "vm" {
  source = "./modules/vm"

  resource_name_prefix   = var.resource_name_prefix
  resource_group_name    = azurerm_resource_group.graphdb.name
  network_interface_name = azurerm_virtual_network.graphdb.name

  graphdb_subnet_name                   = azurerm_subnet.graphdb-vmss.name
  load_balancer_backend_address_pool_id = module.load_balancer.load_balancer_backend_address_pool_id
  load_balancer_fqdn                    = module.load_balancer.load_balancer_fqdn
  identity_name                         = module.identity.identity_name
  key_vault_name                        = module.vault.key_vault_name

  instance_type     = var.instance_type
  image_id          = module.graphdb_image.image_id
  node_count        = var.node_count
  ssh_key           = var.ssh_key
  source_ssh_blocks = var.source_ssh_blocks

  custom_user_data = var.custom_graphdb_vm_user_data

  tags = local.tags

  depends_on = [
    azurerm_resource_group.graphdb,
    azurerm_virtual_network.graphdb,
    azurerm_subnet.graphdb-vmss,
    # Needed because the license is being created at the same time as the machines.
    module.configuration
  ]
}
