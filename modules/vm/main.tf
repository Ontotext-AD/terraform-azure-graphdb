data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}

locals {
  resource_group = data.azurerm_resource_group.graphdb.name
  location       = data.azurerm_resource_group.graphdb.location
}

# TODO: Move out of here to a sg module ?
# Create Network Security Group and rules
resource "azurerm_network_security_group" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = data.azurerm_resource_group.graphdb.name
  location            = data.azurerm_resource_group.graphdb.location

  # TODO: enable after configuring the load balancer

  #  security_rule {
  #    name                       = "graphdb_network_lb_ingress"
  #    description                = "CIRDs allowed to access GraphDB."
  #    priority                   = 950
  #    direction                  = "Inbound"
  #    access                     = "Allow"
  #    protocol                   = "Tcp"
  #    source_port_range          = "*"
  #    destination_port_range     = "7200"
  #    source_address_prefixes    = local.subnet_cidr_blocks
  #    destination_address_prefix = "*"
  #  }
  #
  #  security_rule {
  #    name                       = "graphdb_lb_healthchecks"
  #    description                = "Allow the load balancer to healthcheck the GraphDB nodes and access the proxies."
  #    priority                   = 1001
  #    direction                  = "Inbound"
  #    access                     = "Allow"
  #    protocol                   = "Tcp"
  #    source_port_range          = "7200"
  #    destination_port_range     = "7201"
  #    source_address_prefixes    = local.subnet_cidr_blocks
  #    destination_address_prefix = "*"
  #  }
  #
  #  security_rule {
  #    name                       = "graphdb_internal_http"
  #    description                = "Allow GraphDB proxies and nodes to communicate (HTTP)."
  #    priority                   = 1002
  #    direction                  = "Inbound"
  #    access                     = "Allow"
  #    protocol                   = "Tcp"
  #    source_port_range          = "7200"
  #    destination_port_range     = "7201"
  #    source_address_prefixes    = local.subnet_cidr_blocks
  #    destination_address_prefix = "*"
  #  }
  #
  #  security_rule {
  #    name                       = "graphdb_internal_raft"
  #    description                = "Allow GraphDB proxies and nodes to communicate (Raft)."
  #    priority                   = 1003
  #    direction                  = "Inbound"
  #    access                     = "Allow"
  #    protocol                   = "Tcp"
  #    source_port_range          = "7300"
  #    destination_port_range     = "7301"
  #    source_address_prefixes    = local.subnet_cidr_blocks
  #    destination_address_prefix = "*"
  #  }
  #
  #  security_rule {
  #    name                       = "graphdb_ssh_inbound"
  #    description                = "Allow specified CIDRs SSH access to the GraphDB instances."
  #    priority                   = 900 # Needs to be first priority.
  #    direction                  = "Inbound"
  #    access                     = "Allow"
  #    protocol                   = "Tcp"
  #    source_port_range          = "*"
  #    destination_port_range     = 22
  #    source_address_prefixes    = var.source_ssh_blocks
  #    destination_address_prefix = "*"
  #  }

  # TODO: Remove after configuring the lb
  security_rule {
    name                       = "graphdb_inbound"
    description                = "Allow specified CIDRs SSH access to the GraphDB instances."
    priority                   = 900 # Needs to be first priority.
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = ["0.0.0.0/0"]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "graphdb_outbound"
    description                = "Allow GraphDB nodes to send outbound traffic"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = ["0.0.0.0/0"]
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Create virtual machine
resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = local.resource_group
  location            = local.location

  source_image_id = var.image_id

  zones        = var.zones
  zone_balance = true

  computer_name_prefix = var.resource_name_prefix
  admin_username       = "graphdb"

  sku       = var.instance_type
  instances = var.node_count

  network_interface {
    name                      = "${var.resource_name_prefix}-profile"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.graphdb.id

    ip_configuration {
      name      = "IPConfiguration"
      primary   = true
      subnet_id = var.graphdb_subnet_id

      # TODO: Temporary for testing. Remove after configuring the LB
      public_ip_address {
        name = "first"
      }
    }
  }

  os_disk {
    # TODO: size? caching?
    caching              = "None"
    storage_account_type = "Premium_LRS"
  }

  admin_ssh_key {
    public_key = var.ssh_key
    username   = "graphdb"
  }

  tags = var.tags
}
