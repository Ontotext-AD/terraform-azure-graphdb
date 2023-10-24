data "azurerm_resource_group" "rg" {
  name = var.rg_name
}

data "azurerm_subnet" "subnet" {
  name                 = "gdb-main-subnet"
  resource_group_name  = var.rg_name
  virtual_network_name = var.network_interface_id
  count                = length(var.graphdb_subnets)
}

#data "azurerm_images" "graphdb" {
#  tags_filter         = {} # How does this work?
#  resource_group_name = var.rg_name
#}

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

resource "azurerm_ip_group" "gdb_ip_group" {

  location            = var.azure_region
  name                = "gdb-ip-group"
  resource_group_name = var.rg_name
  cidrs               = [
    "10.0.0.0/19",
    "10.0.32.0/19",
    "10.0.64.0/19",
  ]
}

resource "azurerm_ip_group" "gdb_lb_ip_group" {
  name                = "gdb-ip-lb-group"
  resource_group_name = var.rg_name
  location            = var.azure_region
  cidrs               = [
    "10.0.0.0/19",
    "10.0.32.0/19",
    "10.0.64.0/19",
  ]
}

locals {
  subnet_cidr_blocks = [
    "10.0.0.0/19",
    "10.0.32.0/19",
    "10.0.64.0/19",
  ]
  lb_subnet_cidr_blocks = [
    "10.0.0.0/19",
    "10.0.32.0/19",
    "10.0.64.0/19",
  ]
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
    source_address_prefixes = local.subnet_cidr_blocks
    destination_address_prefix = "*"
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
    source_address_prefixes  = local.subnet_cidr_blocks
    destination_address_prefix = "*"

  }

  security_rule {
    name                   = "graphdb_internal_http"
    description            = "Allow GraphDB proxies and nodes to communicate (HTTP)."
    priority               = 1002
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "7200"
    destination_port_range = "7201"
    source_address_prefixes  = local.subnet_cidr_blocks
    destination_address_prefix = "*"
  }

  security_rule {
    name                   = "graphdb_internal_raft"
    description            = "Allow GraphDB proxies and nodes to communicate (Raft)."
    priority               = 1003
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "7300"
    destination_port_range = "7301"
    source_address_prefixes  = local.subnet_cidr_blocks
    destination_address_prefix = "*"
  }

  security_rule {
    name                    = "graphdb_ssh_inbound"
    description             = "Allow specified CIDRs SSH access to the GraphDB instances."
    priority                = 999 # Needs to be first priority.
    direction               = "Inbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "*"
    destination_port_range  = 22
    source_address_prefixes = var.source_ssh_blocks
    destination_address_prefix = "*"
  }

  security_rule {
    name                    = "graphdb_outbound"
    description             = "Allow GraphDB nodes to send outbound traffic"
    priority                = 1000
    direction               = "Outbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "*"
    destination_port_range  = "*"
    source_address_prefixes = ["0.0.0.0/0"]
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip_prefix" "main" {
  name                = "${var.resource_name_prefix}-gdb-pip"
  location            = var.azure_region
  resource_group_name = var.rg_name
}

# Create virtual machine
resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = "${var.resource_name_prefix}-graphdb"
  location            = var.azure_region
  resource_group_name = var.rg_name
  admin_username      = "graphdb"
  sku                 = var.instance_type
  network_interface {
    primary = true
    name = var.network_interface_id
    network_security_group_id = azurerm_network_security_group.graphdb.id
    ip_configuration {
      name = azurerm_ip_group.gdb_ip_group.name
      primary = true
      subnet_id = data.azurerm_subnet.subnet[0].id
      # Temporary for testing. Deploy only if single instance, otherwise LB?
      public_ip_address {
        name = "first"
      }
    }
  }
  os_disk {
    caching              = "None"
    storage_account_type = "Premium_LRS"
  }
  admin_ssh_key {
    public_key = var.ssh_key
    username   = "graphdb"
  }
  instances       = var.node_count
  source_image_id = var.image_id
}