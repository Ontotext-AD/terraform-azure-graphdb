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
    deployment = var.resource_name_prefix
    # Used to easily track all resource managed by Terraform
    source     = "Terraform"
  }, var.tags)
}

# ------------------------------------------------------------

# TODO: To be moved in another module/example module + configurations

resource "azurerm_resource_group" "graphdb" {
  name     = var.resource_name_prefix
  location = var.location
  tags     = local.tags
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

module "vm" {
  source = "./modules/vm"

  resource_group_name    = azurerm_resource_group.graphdb.name
  network_interface_name = azurerm_virtual_network.graphdb.name

  resource_name_prefix = var.resource_name_prefix
  graphdb_subnet_id    = azurerm_subnet.graphdb-private.id
  instance_type        = var.instance_type
  image_id             = local.image_id
  node_count           = var.node_count
  ssh_key              = var.ssh_key
  source_ssh_blocks    = var.source_ssh_blocks

  tags = local.tags

  depends_on = [azurerm_resource_group.graphdb, azurerm_virtual_network.graphdb, azurerm_subnet.graphdb-private]
}
