# ---------------------------
# RECORDS – PUBLIC
# ---------------------------

resource "azurerm_dns_a_record" "a_public" {
  for_each            = var.private_zone ? {} : local.a_by_name
  name                = each.key
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl
  records             = try(each.value.records, null)
  target_resource_id  = try(each.value.target_resource_id, null)
}

resource "azurerm_dns_cname_record" "cname_public" {
  for_each            = var.private_zone ? {} : local.cname_by_name
  name                = each.key
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl
  record              = each.value.record
  target_resource_id  = try(each.value.target_resource_id, null)
}
