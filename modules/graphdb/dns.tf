# Private DNS zone for internal cluster communication between GraphDB nodes and proxies

resource "azurerm_private_dns_zone" "graphdb" {
  name                = "${var.resource_name_prefix}.dns.zone"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "graphdb" {
  name                = "${var.resource_name_prefix}-dns-link"
  resource_group_name = var.resource_group_name
  virtual_network_id  = var.virtual_network_id

  private_dns_zone_name = azurerm_private_dns_zone.graphdb.name
}
