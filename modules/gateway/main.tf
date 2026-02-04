# Application Gateway

locals {
  gateway_ip_configuration_name                  = "${var.resource_name_prefix}-gateway-ip"
  gateway_frontend_http_port_name                = "${var.resource_name_prefix}-gateway-http"
  gateway_frontend_https_port_name               = "${var.resource_name_prefix}-gateway-https"
  gateway_frontend_ip_configuration_name         = "${var.resource_name_prefix}-gateway-public-ip"
  gateway_backend_address_pool_name              = "${var.resource_name_prefix}-gateway-backend-address-pool"
  gateway_backend_http_settings_name             = "${var.resource_name_prefix}-gateway-backend-http"
  gateway_http_probe_name                        = "${var.resource_name_prefix}-gateway-http-probe"
  gateway_http_listener_name                     = "${var.resource_name_prefix}-gateway-http-listener"
  gateway_https_listener_name                    = "${var.resource_name_prefix}-gateway-https-listener"
  gateway_http_request_routing_rule_name         = "${var.resource_name_prefix}-gateway-http-request-rule"
  gateway_https_request_routing_rule_name        = "${var.resource_name_prefix}-gateway-https-request-rule"
  gateway_redirect_rule_name                     = "${var.resource_name_prefix}-gateway-ssl-redirect"
  gateway_ssl_certificate_name                   = "${var.resource_name_prefix}-ssl"
  gateway_private_link_configuration_name        = "${var.resource_name_prefix}-private-link-configuration"
  gateway_private_link_ip_configuration_name     = "${var.resource_name_prefix}-private-link-ip-configuration"
  gateway_frontend_private_ip_configuration_name = "${var.resource_name_prefix}-private-ip"
  clean_context_path                             = trim(var.context_path, "/")
}

# Public Application Gateway
resource "azurerm_application_gateway" "graphdb-public" {
  count = var.gateway_enable_private_access ? 0 : 1

  name                = "agw-${var.resource_name_prefix}-public"
  resource_group_name = var.resource_group_name
  location            = var.location

  autoscale_configuration {
    min_capacity = var.gateway_min_capacity
    max_capacity = var.gateway_max_capacity
  }

  global {
    request_buffering_enabled  = var.gateway_global_request_buffering_enabled
    response_buffering_enabled = var.gateway_global_response_buffering_enabled
  }

  dynamic "private_link_configuration" {
    for_each = var.gateway_enable_private_link_service ? [1] : []

    content {
      name = local.gateway_private_link_configuration_name

      ip_configuration {
        name                          = local.gateway_private_link_ip_configuration_name
        subnet_id                     = azurerm_subnet.graphdb_private_link_subnet[0].id
        primary                       = true
        private_ip_address_allocation = "Dynamic"
      }
    }
  }

  enable_http2 = true

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.gateway_tls_certificate_identity_id]
  }

  ssl_certificate {
    name                = local.gateway_ssl_certificate_name
    key_vault_secret_id = var.gateway_tls_certificate_secret_id
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = var.gateway_ssl_policy_profile
  }

  # Gateway subnet association
  gateway_ip_configuration {
    name      = local.gateway_ip_configuration_name
    subnet_id = var.gateway_subnet_id
  }

  # HTTP port
  frontend_port {
    name = local.gateway_frontend_http_port_name
    port = 80
  }

  # HTTPS port
  frontend_port {
    name = local.gateway_frontend_https_port_name
    port = 443
  }

  frontend_ip_configuration {
    name                            = local.gateway_frontend_ip_configuration_name
    public_ip_address_id            = azurerm_public_ip.graphdb_public_ip_address.id
    private_link_configuration_name = var.gateway_enable_private_link_service ? local.gateway_private_link_configuration_name : null
  }

  backend_address_pool {
    name = local.gateway_backend_address_pool_name
  }

  # HTTP probe checking GraphDB instances
  probe {
    name = local.gateway_http_probe_name

    host                = "127.0.0.1"
    path                = var.node_count != 1 ? "/rest/cluster/node/status" : "/protocol"
    port                = var.node_count != 1 ? 7201 : 7200
    protocol            = var.gateway_backend_protocol
    interval            = var.gateway_probe_interval
    timeout             = var.gateway_probe_timeout
    unhealthy_threshold = var.gateway_probe_threshold
  }

  backend_http_settings {
    name            = local.gateway_backend_http_settings_name
    path            = var.gateway_backend_path
    port            = var.node_count != 1 ? 7201 : 7200
    protocol        = var.gateway_backend_protocol
    request_timeout = var.gateway_backend_request_timeout

    # Use dedicated HTTP probe
    probe_name = local.gateway_http_probe_name

    cookie_based_affinity = "Disabled"
  }

  # HTTP listener
  http_listener {
    name                           = local.gateway_http_listener_name
    frontend_ip_configuration_name = local.gateway_frontend_ip_configuration_name
    frontend_port_name             = local.gateway_frontend_http_port_name
    protocol                       = "Http"
  }

  # HTTPS listener
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

  # HTTP request routing rule
  request_routing_rule {
    name                        = local.gateway_http_request_routing_rule_name
    priority                    = 1
    rule_type                   = "Basic"
    http_listener_name          = local.gateway_http_listener_name
    redirect_configuration_name = local.gateway_redirect_rule_name
  }

  # HTTPS request - Path-Based routing rule
  # Conditionally create a request routing rule based on the var.context_path
  dynamic "request_routing_rule" {
    for_each = var.context_path != null && var.context_path != "" ? [1] : []

    content {
      name               = local.gateway_https_request_routing_rule_name
      priority           = 10
      rule_type          = "PathBasedRouting"
      http_listener_name = local.gateway_https_listener_name
      url_path_map_name  = "path-map"
    }
  }

  # HTTPS request Basic routing rule
  # Fallback to a Basic Rule when var.context_path is empty
  dynamic "request_routing_rule" {
    for_each = var.context_path == null || var.context_path == "" ? [1] : []

    content {
      name                       = local.gateway_https_request_routing_rule_name
      priority                   = 10
      rule_type                  = "Basic"
      http_listener_name         = local.gateway_https_listener_name
      backend_address_pool_name  = local.gateway_backend_address_pool_name
      backend_http_settings_name = local.gateway_backend_http_settings_name
    }
  }

  dynamic "url_path_map" {
    for_each = var.context_path != null && var.context_path != "" ? [1] : []

    content {
      name                               = "path-map"
      default_backend_address_pool_name  = local.gateway_backend_address_pool_name
      default_backend_http_settings_name = local.gateway_backend_http_settings_name

      path_rule {
        name                       = "context-path-rule"
        paths                      = ["/${local.clean_context_path}/*"]
        backend_address_pool_name  = local.gateway_backend_address_pool_name
        backend_http_settings_name = local.gateway_backend_http_settings_name
      }
    }
  }
}

# Private Application Gateway
resource "azurerm_application_gateway" "graphdb-private" {
  count = var.gateway_enable_private_access ? 1 : 0

  name                = "agw-${var.resource_name_prefix}-private"
  resource_group_name = var.resource_group_name
  location            = var.location

  global {
    request_buffering_enabled  = var.gateway_global_request_buffering_enabled
    response_buffering_enabled = var.gateway_global_response_buffering_enabled
  }

  dynamic "private_link_configuration" {
    for_each = var.gateway_enable_private_link_service ? [1] : []

    content {
      name = local.gateway_private_link_configuration_name

      ip_configuration {
        name                          = local.gateway_private_link_ip_configuration_name
        subnet_id                     = azurerm_subnet.graphdb_private_link_subnet[0].id
        primary                       = true
        private_ip_address_allocation = "Dynamic"
      }
    }
  }

  autoscale_configuration {
    min_capacity = var.gateway_min_capacity
    max_capacity = var.gateway_max_capacity
  }

  enable_http2 = true

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.gateway_tls_certificate_identity_id]
  }

  ssl_certificate {
    name                = local.gateway_ssl_certificate_name
    key_vault_secret_id = var.gateway_tls_certificate_secret_id
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = var.gateway_ssl_policy_profile
  }

  # Gateway subnet association
  gateway_ip_configuration {
    name      = local.gateway_ip_configuration_name
    subnet_id = var.gateway_subnet_id
  }

  # HTTP port
  frontend_port {
    name = local.gateway_frontend_http_port_name
    port = 80
  }

  # HTTPS port
  frontend_port {
    name = local.gateway_frontend_https_port_name
    port = 443
  }

  # Application Gateway enforces to assign a public IP address but we don't add listeners on it
  frontend_ip_configuration {
    name                 = local.gateway_frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.graphdb_public_ip_address.id
  }

  # Private IP address
  frontend_ip_configuration {
    name                            = local.gateway_frontend_private_ip_configuration_name
    private_ip_address_allocation   = "Static"
    private_ip_address              = cidrhost(var.gateway_subnet_address_prefixes[0], 4)
    subnet_id                       = var.gateway_subnet_id
    private_link_configuration_name = var.gateway_enable_private_link_service ? local.gateway_private_link_configuration_name : null
  }

  backend_address_pool {
    name = local.gateway_backend_address_pool_name
  }

  # HTTP probe checking GraphDB instances
  probe {
    name = local.gateway_http_probe_name

    host                = "127.0.0.1"
    path                = var.node_count != 1 ? "/rest/cluster/node/status" : "/protocol"
    port                = var.node_count != 1 ? 7201 : 7200
    protocol            = var.gateway_backend_protocol
    interval            = var.gateway_probe_interval
    timeout             = var.gateway_probe_timeout
    unhealthy_threshold = var.gateway_probe_threshold
  }

  backend_http_settings {
    name            = local.gateway_backend_http_settings_name
    path            = var.gateway_backend_path
    port            = var.node_count != 1 ? 7201 : 7200
    protocol        = var.gateway_backend_protocol
    request_timeout = var.gateway_backend_request_timeout

    # Use dedicated HTTP probe
    probe_name = local.gateway_http_probe_name

    cookie_based_affinity = "Disabled"
  }

  # HTTP listener
  http_listener {
    name                           = local.gateway_http_listener_name
    frontend_ip_configuration_name = local.gateway_frontend_private_ip_configuration_name
    frontend_port_name             = local.gateway_frontend_http_port_name
    protocol                       = "Http"
  }

  # HTTPS listener
  http_listener {
    name                           = local.gateway_https_listener_name
    frontend_ip_configuration_name = local.gateway_frontend_private_ip_configuration_name
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

  # HTTP request routing rule
  request_routing_rule {
    name                        = local.gateway_http_request_routing_rule_name
    priority                    = 1
    rule_type                   = "Basic"
    http_listener_name          = local.gateway_http_listener_name
    redirect_configuration_name = local.gateway_redirect_rule_name
  }

  # HTTPS request routing rule
  request_routing_rule {
    name                       = local.gateway_https_request_routing_rule_name
    priority                   = 10
    rule_type                  = "Basic"
    http_listener_name         = local.gateway_https_listener_name
    backend_address_pool_name  = local.gateway_backend_address_pool_name
    backend_http_settings_name = local.gateway_backend_http_settings_name
  }
}
