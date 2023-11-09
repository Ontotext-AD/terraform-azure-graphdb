data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}

resource "azurerm_user_assigned_identity" "graphdb-instances" {
  name                = "${var.resource_name_prefix}-vmss"
  resource_group_name = data.azurerm_resource_group.graphdb.name
  location            = data.azurerm_resource_group.graphdb.location

  tags = var.tags
}
