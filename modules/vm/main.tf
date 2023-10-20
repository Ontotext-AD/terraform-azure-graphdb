data "azurerm_resource_group" "rg" {
  name     = var.rg_name
}

data "azurerm_subnet" "subnet" {
  name                 = "gdb-main-subnet"
  resource_group_name  = var.rg_name
  virtual_network_name = var.network_interface_id
  count                = length(var.graphdb_subnets)
}

data "azurerm_images" "graphdb" {
  tags_filter         = {} # How does this work?
  resource_group_name = var.rg_name
}

data "azurerm_subnet" "lb_subnets" {
  name                 = "gdb-lb-subnet"
  resource_group_name  = var.rg_name
  virtual_network_name = var.network_interface_id
  count                = length(var.lb_subnets)
}

data "azurerm_virtual_network" "vn" {
  name                = var.network_interface_id
  resource_group_name = var.rg_name
}

data "azurerm_ip_group" "gdb_ip_group" {
  name                = "gdb-ip-group"
  resource_group_name = var.rg_name
}

data "azurerm_ip_group" "gdb_lb_ip_group" {
  name                = "gdb-ip-lb-group"
  resource_group_name = var.rg_name
}

locals {
  subnet_cidr_blocks    = [for s in data.azurerm_ip_group.gdb_ip_group : s.cidrs]
  lb_subnet_cidr_blocks = [for s in data.azurerm_ip_group.gdb_lb_ip_group : s.cidrs]
}

# Create Network Security Group and rules
resource "azurerm_network_security_group" "graphdb" {
  name                = "${var.resource_name_prefix}-graphdb"
  location            = var.azure_region
  resource_group_name = var.rg_name

  security_rule {
    name                    = "graphdb_network_lb_ingress"
    description             = "CIRDs allowed to access GraphDB."
    priority                = 1000
    direction               = "Inbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "7200"
    destination_port_range  = "7200"
    source_address_prefixes = var.allowed_inbound_cidrs
  }
  security_rule {
    name                   = "graphdb_lb_healthchecks"
    description            = "Allow the load balancer to healthcheck the GraphDB nodes and access the proxies."
    priority               = 1001
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "7200"
    destination_port_range = "7201"
    source_address_prefix  = local.lb_subnet_cidr_blocks
  }

  security_rule {
    name                   = "graphdb_internal_http"
    description            = "Allow GraphDB proxies and nodes to communicate (HTTP)."
    priority               = 1001
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "7200"
    destination_port_range = "7201"
    source_address_prefix  = local.subnet_cidr_blocks
  }

  security_rule {
    name                   = "graphdb_internal_raft"
    description            = "Allow GraphDB proxies and nodes to communicate (Raft)."
    priority               = 1001
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "7300"
    destination_port_range = "7301"
    source_address_prefix  = local.subnet_cidr_blocks
  }

  security_rule {
    name                    = "graphdb_ssh_inbound"
    description             = "Allow specified CIDRs SSH access to the GraphDB instances."
    priority                = 1001
    direction               = "Inbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "7300"
    destination_port_range  = "7301"
    source_address_prefixes = local.subnet_cidr_blocks
  }

  security_rule {
    name                   = "graphdb_outbound"
    description            = "Allow GraphDB nodes to send outbound traffic"
    priority               = 1001
    direction              = "Outbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "*"
    destination_port_range = "*"
    source_address_prefixes  = ["0.0.0.0/0"]
  }
}

# Create virtual machine
resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = "${var.resource_name_prefix}-graphdb"
  location            = var.azure_region
  resource_group_name = var.rg_name
  admin_username      = "graphdb"
  sku                 = var.instance_type
  network_interface {
    name = var.network_interface_id
    ip_configuration {
      name = data.azurerm_ip_group.gdb_ip_group.name
    }
  }
  os_disk {
    caching              = "None"
    storage_account_type = "Premium_LRS"
  }
  instances       = var.node_count
  source_image_id = var.image_id
}