# Network security

resource "azurerm_network_security_group" "graphdb_gateway" {
  name                = "nsg-${var.resource_name_prefix}-gateway"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                       = "AllowGatewayManager"
    description                = "Allows Gateway Manager to perform health monitoring"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "GatewayManager"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "65200-65535"
  }

  security_rule {
    name                         = "AllowLoadBalancer"
    description                  = "Allows AzureLoadBalancer to perform balancing to gateway instances"
    priority                     = 110
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_address_prefix        = "AzureLoadBalancer"
    source_port_range            = "*"
    destination_address_prefixes = var.gateway_subnet_address_prefixes
    destination_port_range       = "*"
  }

  dynamic "security_rule" {
    for_each = var.gateway_allowed_address_prefix != null && length(var.gateway_allowed_address_prefix) > 0 ? [1] : []
    content {
      name                         = "AllowInBoundAddress"
      priority                     = 200
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "Tcp"
      source_address_prefix        = var.gateway_allowed_address_prefix
      source_port_range            = "*"
      destination_address_prefixes = var.gateway_subnet_address_prefixes
      destination_port_ranges      = [80, 443]
    }
  }

  dynamic "security_rule" {
    for_each = length(var.gateway_allowed_address_prefixes) > 0 ? [1] : []
    content {
      name                         = "AllowInBoundAddresses"
      priority                     = 201
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "Tcp"
      source_address_prefixes      = var.gateway_allowed_address_prefixes
      source_port_range            = "*"
      destination_address_prefixes = var.gateway_subnet_address_prefixes
      destination_port_ranges      = [80, 443]
    }
  }

  dynamic "security_rule" {
    for_each = var.gateway_enable_private_link_service ? [1] : []
    content {
      name                         = "AllowPrivateLinkInBoundHttp"
      description                  = "Allows HTTP inbound traffic from the private link subnet to the private frontend IP"
      priority                     = 300
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "Tcp"
      source_address_prefixes      = var.gateway_private_link_subnet_address_prefixes
      source_port_range            = "*"
      destination_address_prefixes = var.gateway_subnet_address_prefixes
      destination_port_ranges      = [80, 443]
    }
  }

  # Deny anything else
  security_rule {
    name                         = "DenyInBound"
    description                  = "Denies any other inbound traffic to the associated subnet"
    priority                     = 4096
    direction                    = "Inbound"
    access                       = "Deny"
    protocol                     = "*"
    source_address_prefix        = "*"
    source_port_range            = "*"
    destination_address_prefixes = var.gateway_subnet_address_prefixes
    destination_port_range       = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "graphdb_gateway" {
  network_security_group_id = azurerm_network_security_group.graphdb_gateway.id
  subnet_id                 = var.gateway_subnet_id
}
