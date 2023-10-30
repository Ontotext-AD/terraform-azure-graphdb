provider "azurerm" {
  features {
    managed_disk {
      expand_without_downtime = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
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

# TODO: To be moved in another module/example module + configurations

resource "azurerm_resource_group" "graphdb" {
  name     = var.resource_name_prefix
  location = var.location
  tags     = local.tags
}

resource "azurerm_management_lock" "graphdb-rg-lock" {
  name       = "${var.resource_name_prefix}-rg"
  lock_level = "CanNotDelete"
  scope      = azurerm_resource_group.graphdb.id
  notes      = "Prevents deleting the resource group"
}

resource "azurerm_virtual_network" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = azurerm_resource_group.graphdb.name
  location            = azurerm_resource_group.graphdb.location
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "graphdb-private" {
  name                 = "${var.resource_name_prefix}-private"
  resource_group_name  = azurerm_resource_group.graphdb.name
  virtual_network_name = azurerm_virtual_network.graphdb.name
  address_prefixes     = ["10.0.2.0/24"]
}

# ------------------------------------------------------------

# TODO: Could go into another module

# TODO: Config + how to .. refer other account group?
data "azurerm_resource_group" "image" {
  name = "Packer-RG"
}

# TODO: Support for multiple architectures
data "azurerm_shared_image_version" "graphdb" {
  name                = "latest"
  image_name          = "${var.graphdb_version}-x86_64"
  gallery_name        = "GraphDB"
  resource_group_name = data.azurerm_resource_group.image.name
}

locals {
  image_id = var.image_id != null ? var.image_id : data.azurerm_shared_image_version.graphdb.id
}

# ------------------------------------------------------------

module "load_balancer" {
  source = "./modules/load_balancer"

  resource_name_prefix = var.resource_name_prefix
  resource_group_name  = azurerm_resource_group.graphdb.name

  tags = local.tags

  depends_on = [azurerm_resource_group.graphdb, azurerm_virtual_network.graphdb]
}

module "vm" {
  source = "./modules/vm"

  resource_name_prefix   = var.resource_name_prefix
  resource_group_name    = azurerm_resource_group.graphdb.name
  network_interface_name = azurerm_virtual_network.graphdb.name

  graphdb_subnet_name                   = azurerm_subnet.graphdb-private.name
  load_balancer_backend_address_pool_id = module.load_balancer.load_balancer_backend_address_pool_id
  load_balancer_fqdn                    = module.load_balancer.load_balancer_fqdn

  instance_type     = var.instance_type
  image_id          = local.image_id
  node_count        = var.node_count
  ssh_key           = var.ssh_key
  source_ssh_blocks = var.source_ssh_blocks

  tags = local.tags

  depends_on = [azurerm_resource_group.graphdb, azurerm_virtual_network.graphdb, azurerm_subnet.graphdb-private]
}
