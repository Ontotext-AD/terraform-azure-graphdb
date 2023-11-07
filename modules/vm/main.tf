data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}

data "azurerm_subnet" "graphdb" {
  name                 = var.graphdb_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.network_interface_name
}

locals {
  resource_group = data.azurerm_resource_group.graphdb.name
  location       = data.azurerm_resource_group.graphdb.location

  subnet_id   = data.azurerm_subnet.graphdb.id
  subnet_cidr = data.azurerm_subnet.graphdb.address_prefix
}

# TODO: Move out of here to a sg module ?
# Create Network Security Group and rules
resource "azurerm_network_security_group" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = local.resource_group
  location            = local.location

  security_rule {
    name                       = "graphdb_internal_http"
    description                = "Allow GraphDB proxies and nodes to communicate (HTTP)."
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "7200"
    source_address_prefixes    = [local.subnet_cidr]
    destination_address_prefix = local.subnet_cidr
  }

  security_rule {
    name                       = "graphdb_internal_raft"
    description                = "Allow GraphDB proxies and nodes to communicate (Raft)."
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "7300"
    source_address_prefixes    = [local.subnet_cidr]
    destination_address_prefix = local.subnet_cidr
  }

  security_rule {
    name                       = "graphdb_ssh_inbound"
    description                = "Allow specified CIDRs SSH access to the GraphDB instances."
    priority                   = 900 # Needs to be first priority.
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = 22
    source_address_prefixes    = var.source_ssh_blocks
    destination_address_prefix = local.subnet_cidr
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
    source_address_prefixes    = [local.subnet_cidr]
    destination_address_prefix = "0.0.0.0/0"
  }

  tags = var.tags
}

locals {
  # TODO: Add support for user provided one?
  user_data_script = templatefile("${path.module}/templates/entrypoint.sh.tpl", {
    load_balancer_fqdn : var.load_balancer_fqdn
  })
}

# Create virtual machine
resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = local.resource_group
  location            = local.location

  source_image_id = var.image_id
  user_data       = base64encode(local.user_data_script)

  sku          = var.instance_type
  instances    = var.node_count
  zones        = var.zones
  zone_balance = true
  upgrade_mode = "Manual"

  computer_name_prefix = "${var.resource_name_prefix}-"
  admin_username       = "graphdb"

  network_interface {
    name                      = "${var.resource_name_prefix}-profile"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.graphdb.id

    ip_configuration {
      name      = "IPConfiguration"
      primary   = true
      subnet_id = local.subnet_id

      load_balancer_backend_address_pool_ids = [var.load_balancer_backend_address_pool_id]

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
