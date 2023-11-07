data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}

locals {
  resource_group = data.azurerm_resource_group.graphdb.name
  location       = data.azurerm_resource_group.graphdb.location
}

resource "random_string" "fqdn" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# TODO: TLS support

# TODO: Should be provided ?
# TODO: Routing preference is set by default to MS network
resource "azurerm_public_ip" "graphdb-load-balancer" {
  name                = "${var.resource_name_prefix}-load-balancer"
  resource_group_name = local.resource_group
  location            = local.location

  sku               = "Standard"
  allocation_method = "Static"
  zones             = var.zones
  # TODO: Should be provided
  domain_name_label = "${var.resource_name_prefix}-${random_string.fqdn.result}"

  tags = var.tags
}

# TODO: Configure the conn/session timeout
# ^ potential issue, in the web console, it's not possible to use anything above 30min

resource "azurerm_lb" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = local.resource_group
  location            = local.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "${var.resource_name_prefix}-PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.graphdb-load-balancer.id
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "graphdb" {
  name            = "${var.resource_name_prefix}-BackEndAddressPool"
  loadbalancer_id = azurerm_lb.graphdb.id
}

resource "azurerm_lb_probe" "graphdb" {
  loadbalancer_id = azurerm_lb.graphdb.id

  name                = "http-probe"
  port                = var.backend_port
  protocol            = "Http"
  request_path        = var.load_balancer_probe_path
  interval_in_seconds = var.load_balancer_probe_interval
  probe_threshold     = var.load_balancer_probe_threshold
}

resource "azurerm_lb_rule" "graphdb" {
  loadbalancer_id          = azurerm_lb.graphdb.id
  probe_id                 = azurerm_lb_probe.graphdb.id
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.graphdb.id]

  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = var.backend_port
  frontend_ip_configuration_name = "${var.resource_name_prefix}-PublicIPAddress"
}
