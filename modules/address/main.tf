resource "random_string" "fqdn" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_public_ip" "graphdb_public_ip_address" {
  name                = "${var.resource_name_prefix}-public-address"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku               = "Standard"
  allocation_method = "Static"
  zones             = var.zones

  # TODO: idle_timeout_in_minutes is between 4 and 30 minutes, gotta test if this affects our data loading

  domain_name_label = "${var.resource_name_prefix}-${random_string.fqdn.result}"
}
