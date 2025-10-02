locals {
  a_records_input     = var.a_records_list
  a_by_name           = { for r in local.a_records_input : r.name => r }
  cname_records_input = var.cname_records_list
  cname_by_name       = { for r in local.cname_records_input : r.name => r }
}

# ---------------------------
# Zone (public OR private)
# ---------------------------

resource "azurerm_dns_zone" "public" {
  count = var.private_zone ? 0 : 1

  name                = var.zone_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone" "private" {
  count = var.private_zone ? 1 : 0

  name                = var.zone_name
  resource_group_name = var.resource_group_name
}

# Private DNS virtual network links (only for private zones)

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each = var.private_zone ? var.private_zone_vnet_links : {}

  name                  = coalesce(each.value.name, "${each.key}-link")
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.private[0].name
  virtual_network_id    = each.value.virtual_network_id
  registration_enabled  = try(each.value.registration_enabled, false)
}
