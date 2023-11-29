resource "azurerm_private_dns_zone" "zone" {
  name                = "${var.resource_name_prefix}.dns.zone"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "zone_link" {
  name                  = "${var.resource_name_prefix}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zone.name
  virtual_network_id    = var.virtual_network_id
  tags                  = var.tags
}
