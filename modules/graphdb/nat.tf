#
# NAT Gateway
#

locals {
  # Choose one of the zones for single zone NAT
  nat_zone = var.zones[0]
}

resource "azurerm_public_ip" "graphdb_nat_gateway" {
  name                = "pip-${var.resource_name_prefix}-nat-gateway"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku               = "Standard"
  allocation_method = "Static"
  zones             = [local.nat_zone]

  idle_timeout_in_minutes = var.nat_gateway_pip_idle_timeout
}

resource "azurerm_nat_gateway" "graphdb" {
  name                = "ng-${var.resource_name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku_name                = "Standard"
  zones                   = [local.nat_zone]
  idle_timeout_in_minutes = 10 # TODO: 120 is the max in the portal, gotta test with long running request
}

resource "azurerm_nat_gateway_public_ip_association" "graphdb_nat_gateway" {
  nat_gateway_id       = azurerm_nat_gateway.graphdb.id
  public_ip_address_id = azurerm_public_ip.graphdb_nat_gateway.id
}

resource "azurerm_subnet_nat_gateway_association" "graphdb_nat_gateway" {
  nat_gateway_id = azurerm_nat_gateway.graphdb.id
  subnet_id      = var.graphdb_subnet_id
}
