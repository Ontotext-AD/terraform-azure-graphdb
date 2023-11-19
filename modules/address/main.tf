data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}

locals {
  resource_group = data.azurerm_resource_group.graphdb.name
  location       = data.azurerm_resource_group.graphdb.location
}

resource "random_string" "fqdn" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_public_ip" "graphdb-public-ip-address" {
  name                = "${var.resource_name_prefix}-public-address"
  resource_group_name = local.resource_group
  location            = local.location

  sku               = "Standard"
  allocation_method = "Static"
  zones             = var.zones

  # TODO: idle_timeout_in_minutes is between 4 and 30 minutes, gotta test if this affects our data loading

  domain_name_label = "${var.resource_name_prefix}-${random_string.fqdn.result}"

  tags = var.tags
}
