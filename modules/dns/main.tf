data "azurerm_resource_group" "graphdb" {
  name = var.resource_name_prefix
}

data "azurerm_user_assigned_identity" "graphdb-instances" {
  name                = var.identity_name
  resource_group_name = var.resource_name_prefix
}

data "azurerm_virtual_network" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = data.azurerm_resource_group.graphdb.name
}

resource "azurerm_private_dns_zone" "zone" {
  name                = "${var.resource_name_prefix}.dns.zone"
  resource_group_name = data.azurerm_resource_group.graphdb.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "zone_link" {
  name                  = "${var.resource_name_prefix}-dns-link"
  resource_group_name   = data.azurerm_resource_group.graphdb.name
  private_dns_zone_name = azurerm_private_dns_zone.zone.name
  virtual_network_id    = data.azurerm_virtual_network.graphdb.id
  registration_enabled  = true
}

resource "azurerm_role_assignment" "dns_zone_role_assignment" {
  principal_id         = data.azurerm_user_assigned_identity.graphdb-instances.principal_id
  role_definition_name = "DNS Zone Contributor"
  scope                = azurerm_private_dns_zone_virtual_network_link.zone_link.id
}
