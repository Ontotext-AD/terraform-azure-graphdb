resource "azurerm_subnet" "graphdb_bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.bastion_subnet_address_prefix
}

resource "azurerm_network_security_group" "graphdb_bastion" {
  name                = "${var.resource_name_prefix}-bastion"
  resource_group_name = var.resource_group_name
  location            = var.location

  # The following rules are required by Azure Bastion in order to function properly
  # See https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
  # See https://learn.microsoft.com/en-gb/azure/bastion/native-client#secure

  # INBOUND

  security_rule {
    name                       = "AllowHTTPSInternetInbound"
    description                = "Allows specified CIDRs to access the Bastion subnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = var.bastion_allowed_cidr_blocks
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = 443
  }

  security_rule {
    name                       = "AllowGatewayManagerInbound"
    description                = "Allows Gateway Manager to perform system operations"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "GatewayManager"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = 443
  }

  # OUTBOUND

  security_rule {
    name                       = "AllowSSHOutbound"
    description                = "Allows outbound SSH/RDP connections"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_ranges    = [22, 3389]
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    description                = "Allows outbound connections to Azure Cloud services"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "AzureCloud"
    destination_port_range     = 443
  }
}

resource "azurerm_subnet_network_security_group_association" "graphdb_bastion" {
  network_security_group_id = azurerm_network_security_group.graphdb_bastion.id
  subnet_id                 = azurerm_subnet.graphdb_bastion.id
}

resource "azurerm_public_ip" "graphdb_bastion" {
  name                = "${var.resource_name_prefix}_bastion_publicIP"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "graphdb" {
  name                = "${var.resource_name_prefix}_bastion"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Enables additional features such as native client support (Azure CLI)
  sku               = "Standard"
  tunneling_enabled = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.graphdb_bastion.id
    public_ip_address_id = azurerm_public_ip.graphdb_bastion.id
  }
}
