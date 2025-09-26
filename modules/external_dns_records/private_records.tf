# ---------------------------
# RECORDS – PRIVATE
# ---------------------------

resource "azurerm_private_dns_a_record" "a_private" {
  for_each            = var.private_zone ? local.a_by_name : {}
  name                = each.key
  zone_name           = azurerm_private_dns_zone.private[0].name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl
  records             = try(each.value.records, null)
}

resource "azurerm_private_dns_cname_record" "cname_private" {
  for_each            = var.private_zone ? local.cname_by_name : {}
  name                = each.key
  zone_name           = azurerm_private_dns_zone.private[0].name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl
  record              = each.value.record
}
