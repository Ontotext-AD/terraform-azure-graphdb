resource "azurerm_subnet" "graphdb_private_link_subnet" {
  count = var.gateway_enable_private_link_service ? 1 : 0

  name                                          = "snet-${var.resource_name_prefix}-private-link"
  resource_group_name                           = var.resource_group_name
  virtual_network_name                          = var.virtual_network_name
  address_prefixes                              = var.gateway_private_link_subnet_address_prefixes
  private_link_service_network_policies_enabled = var.gateway_private_link_service_network_policies_enabled
}
