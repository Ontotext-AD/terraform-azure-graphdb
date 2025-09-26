# Optionally create Resource Group
resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.resource_group_location
}

locals {
  rg_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
}

# ---------------------------
# Zone (public OR private)
# ---------------------------

resource "azurerm_dns_zone" "public" {
  count               = var.private_zone ? 0 : 1
  name                = var.zone_name
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone" "private" {
  count               = var.private_zone ? 1 : 0
  name                = var.zone_name
  resource_group_name = local.rg_name
}

# Private DNS virtual network links (only for private zones)
resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = var.private_zone ? var.private_zone_vnet_links : {}
  name                  = coalesce(each.value.name, "${each.key}-link")
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.private[0].name
  virtual_network_id    = each.value.virtual_network_id
  registration_enabled  = try(each.value.registration_enabled, false)
}

# ---------------------------
# RECORDS – PUBLIC
# ---------------------------

# A
resource "azurerm_dns_a_record" "a_public" {
  for_each            = var.private_zone ? {} : var.a_records
  name                = each.key
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  records             = try(each.value.records, null)
  target_resource_id  = try(each.value.target_resource_id, null)
}

# CNAME
resource "azurerm_dns_cname_record" "cname_public" {
  for_each            = var.private_zone ? {} : var.cname_records
  name                = each.key
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  record              = each.value.record
  target_resource_id  = try(each.value.target_resource_id, null)
}

# TXT
resource "azurerm_dns_txt_record" "txt_public" {
  for_each            = var.private_zone ? {} : var.txt_records
  name                = each.key
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  dynamic "record" {
    for_each = each.value.records
    content {
      value = record.value
    }
  }
}

# MX
resource "azurerm_dns_mx_record" "mx_public" {
  for_each            = var.private_zone ? {} : var.mx_records
  name                = each.key
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  dynamic "record" {
    for_each = each.value.records
    content {
      preference = record.value.preference
      exchange   = record.value.exchange
    }
  }
}

# NS
resource "azurerm_dns_ns_record" "ns_public" {
  for_each            = var.private_zone ? {} : var.ns_records
  name                = each.key
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  records             = each.value.records
}

# SRV
resource "azurerm_dns_srv_record" "srv_public" {
  for_each            = var.private_zone ? {} : var.srv_records
  name                = each.key
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  dynamic "record" {
    for_each = each.value.records
    content {
      priority = record.value.priority
      weight   = record.value.weight
      port     = record.value.port
      target   = record.value.target
    }
  }
}


# ---------------------------
# RECORDS – PRIVATE
# ---------------------------

resource "azurerm_private_dns_a_record" "a_private" {
  for_each            = var.private_zone ? var.a_records : {}
  name                = each.key
  zone_name           = azurerm_private_dns_zone.private[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  records             = try(each.value.records, null)
}

resource "azurerm_private_dns_cname_record" "cname_private" {
  for_each            = var.private_zone ? var.cname_records : {}
  name                = each.key
  zone_name           = azurerm_private_dns_zone.private[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  record              = each.value.record
}

resource "azurerm_private_dns_txt_record" "txt_private" {
  for_each            = var.private_zone ? var.txt_records : {}
  name                = each.key
  zone_name           = azurerm_private_dns_zone.private[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  dynamic "record" {
    for_each = each.value.records
    content {
      value = record.value
    }
  }
}

resource "azurerm_private_dns_mx_record" "mx_private" {
  for_each            = var.private_zone ? var.mx_records : {}
  name                = each.key
  zone_name           = azurerm_private_dns_zone.private[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  dynamic "record" {
    for_each = each.value.records
    content {
      preference = record.value.preference
      exchange   = record.value.exchange
    }
  }
}

resource "azurerm_private_dns_srv_record" "srv_private" {
  for_each            = var.private_zone ? var.srv_records : {}
  name                = each.key
  zone_name           = azurerm_private_dns_zone.private[0].name
  resource_group_name = local.rg_name
  ttl                 = each.value.ttl
  dynamic "record" {
    for_each = each.value.records
    content {
      priority = record.value.priority
      weight   = record.value.weight
      port     = record.value.port
      target   = record.value.target
    }
  }
}
