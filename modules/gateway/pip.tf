# Public IP

resource "random_string" "ip_domain_name_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_public_ip" "graphdb_public_ip_address" {
  name                = "pip-${var.resource_name_prefix}-app-gateway"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku               = "Standard"
  allocation_method = "Static"
  zones             = var.zones
  domain_name_label = "${var.resource_name_prefix}-${random_string.ip_domain_name_suffix.result}"

  idle_timeout_in_minutes = var.gateway_pip_idle_timeout
}
