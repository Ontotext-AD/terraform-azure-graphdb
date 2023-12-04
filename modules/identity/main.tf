resource "azurerm_user_assigned_identity" "graphdb_instances" {
  name                = "${var.resource_name_prefix}-vmss"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}
