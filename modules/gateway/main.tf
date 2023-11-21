locals {
  gateway_ip_configuration_name           = "${var.resource_name_prefix}-gateway-ip"
  gateway_frontend_http_port_name         = "${var.resource_name_prefix}-gateway-http"
  gateway_frontend_https_port_name        = "${var.resource_name_prefix}-gateway-https"
  gateway_frontend_ip_configuration_name  = "${var.resource_name_prefix}-gateway-public-ip"
  gateway_backend_address_pool_name       = "${var.resource_name_prefix}-gateway-backend-address-pool"
  gateway_backend_http_settings_name      = "${var.resource_name_prefix}-gateway-backend-http"
  gateway_http_probe_name                 = "${var.resource_name_prefix}-gateway-http-probe"
  gateway_http_listener_name              = "${var.resource_name_prefix}-gateway-http-listener"
  gateway_https_listener_name             = "${var.resource_name_prefix}-gateway-https-listener"
  gateway_http_request_routing_rule_name  = "${var.resource_name_prefix}-gateway-http-request-rule"
  gateway_https_request_routing_rule_name = "${var.resource_name_prefix}-gateway-https-request-rule"
  gateway_redirect_rule_name              = "${var.resource_name_prefix}-gateway-ssl-redirect"
  gateway_ssl_certificate_name            = "${var.resource_name_prefix}-ssl"
}

resource "azurerm_application_gateway" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = var.resource_group_name
  location            = var.location

  autoscale_configuration {
    min_capacity = var.gateway_min_capacity
    max_capacity = var.gateway_max_capacity
  }

  enable_http2 = true

  # TODO: Connection draining?

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.gateway_identity_id]
  }

  ssl_certificate {
    name                = local.gateway_ssl_certificate_name
    key_vault_secret_id = var.gateway_tls_certificate_secret_id
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_configuration_name
    subnet_id = var.gateway_subnet_id
  }

  # HTTP
  frontend_port {
    name = local.gateway_frontend_http_port_name
    port = 80
  }

  # HTTPS
  frontend_port {
    name = local.gateway_frontend_https_port_name
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.gateway_frontend_ip_configuration_name
    public_ip_address_id = var.gateway_public_ip_id
  }

  backend_address_pool {
    name = local.gateway_backend_address_pool_name
  }

  probe {
    name = local.gateway_http_probe_name

    host                = "127.0.0.1"
    path                = var.gateway_probe_path
    port                = var.gateway_probe_port
    protocol            = var.gateway_backend_protocol
    interval            = var.gateway_probe_interval
    timeout             = var.gateway_probe_timeout
    unhealthy_threshold = var.gateway_probe_threshold
  }

  backend_http_settings {
    name            = local.gateway_backend_http_settings_name
    path            = var.gateway_backend_path
    port            = var.gateway_backend_port
    protocol        = var.gateway_backend_protocol
    request_timeout = var.gateway_backend_request_timeout

    # Use dedicated HTTP probe
    probe_name = local.gateway_http_probe_name

    cookie_based_affinity = "Disabled"
  }

  # HTTP
  http_listener {
    name                           = local.gateway_http_listener_name
    frontend_ip_configuration_name = local.gateway_frontend_ip_configuration_name
    frontend_port_name             = local.gateway_frontend_http_port_name
    protocol                       = "Http"
  }

  # HTTPS
  http_listener {
    name                           = local.gateway_https_listener_name
    frontend_ip_configuration_name = local.gateway_frontend_ip_configuration_name
    frontend_port_name             = local.gateway_frontend_https_port_name
    protocol                       = "Https"
    ssl_certificate_name           = local.gateway_ssl_certificate_name
  }

  # HTTP to HTTPS
  redirect_configuration {
    name                 = local.gateway_redirect_rule_name
    redirect_type        = "Permanent"
    target_listener_name = local.gateway_https_listener_name
    include_path         = true
    include_query_string = true
  }

  # HTTP
  request_routing_rule {
    name                        = local.gateway_http_request_routing_rule_name
    priority                    = 1
    rule_type                   = "Basic"
    http_listener_name          = local.gateway_http_listener_name
    redirect_configuration_name = local.gateway_redirect_rule_name
  }

  # HTTPS
  request_routing_rule {
    name                       = local.gateway_https_request_routing_rule_name
    priority                   = 10
    rule_type                  = "Basic"
    http_listener_name         = local.gateway_https_listener_name
    backend_address_pool_name  = local.gateway_backend_address_pool_name
    backend_http_settings_name = local.gateway_backend_http_settings_name
  }

  tags = var.tags
}
