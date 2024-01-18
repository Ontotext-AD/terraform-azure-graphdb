resource "azurerm_subnet" "graphdb_bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.bastion_subnet_address_prefix
}

resource "azurerm_network_security_group" "graphdb_bastion" {
  name                = "nsg-${var.resource_name_prefix}-bastion"
  resource_group_name = var.resource_group_name
  location            = var.location

  # The following rules are required by Azure Bastion in order to function properly
  # See https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg
  # See https://learn.microsoft.com/en-gb/azure/bastion/native-client#secure

  # INBOUND

  security_rule {
    name                       = "AllowHTTPSInternetInBound"
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
    name                       = "AllowGatewayManagerInBound"
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

  security_rule {
    name                       = "AllowLoadBalancerInBound"
    description                = "Allows Azure Load Balancer health proves"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "AzureLoadBalancer"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = 443
  }

  security_rule {
    name                       = "AllowBastionHostCommunication"
    description                = "Allows Azure Bastion data plane communication"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_ranges    = [8080, 5701]
  }

  security_rule {
    name                       = "DenyInBound"
    description                = "Denies any other inbound traffic"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  # OUTBOUND

  security_rule {
    name                       = "AllowSSHOutBound"
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
    name                       = "AllowAzureCloudOutBound"
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

  security_rule {
    name                       = "AllowBastionCommunication"
    description                = "Allows Azure Bastion data plane communication"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_ranges    = [8080, 5701]
  }

  security_rule {
    name                       = "AllowHttpOutBound"
    description                = "Allows Azure Bastion specifics"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "Internet"
    destination_port_range     = 80
  }

  security_rule {
    name                       = "DenyOutBound"
    description                = "Denies any outbound traffic"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "graphdb_bastion" {
  network_security_group_id = azurerm_network_security_group.graphdb_bastion.id
  subnet_id                 = azurerm_subnet.graphdb_bastion.id
}

resource "azurerm_public_ip" "graphdb_bastion" {
  name                = "pip-${var.resource_name_prefix}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "graphdb" {
  name                = "bas-${var.resource_name_prefix}"
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
