#
# Networking and security
#

resource "azurerm_application_security_group" "graphdb_vmss" {
  name                = "asg-${var.resource_name_prefix}-vmss"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_network_security_group" "graphdb_vmss" {
  name                = "nsg-${var.resource_name_prefix}-vmss"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_subnet_network_security_group_association" "graphdb_vmss" {
  network_security_group_id = azurerm_network_security_group.graphdb_vmss.id
  subnet_id                 = var.graphdb_subnet_id
}

# Inbound rules

resource "azurerm_network_security_rule" "graphdb_allow_inbound" {
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb_vmss.name

  name                                       = "AllowInBound"
  description                                = "Allows inbound access to GraphDB nodes and proxies"
  priority                                   = 100
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_address_prefixes                    = var.graphdb_inbound_address_prefixes
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.graphdb_vmss.id]
  destination_port_range                     = "7200-7201"
}

resource "azurerm_network_security_rule" "graphdb_allow_internal_inbound" {
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb_vmss.name

  name                                       = "AllowInternalGraphDBInBound"
  description                                = "Allows internal traffic between GraphDB nodes and proxies"
  priority                                   = 200
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_application_security_group_ids      = [azurerm_application_security_group.graphdb_vmss.id]
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.graphdb_vmss.id]
  destination_port_ranges                    = ["7200", "7201", "7300", "7301"]
}

resource "azurerm_network_security_rule" "graphdb_allow_ssh_inbound" {
  count = length(var.graphdb_ssh_inbound_address_prefixes) > 0 ? 1 : 0

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb_vmss.name

  name                                       = "AllowSSHInBound"
  description                                = "Allows SSH connections to GraphDB VMs"
  priority                                   = 300
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_address_prefixes                    = var.graphdb_ssh_inbound_address_prefixes
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.graphdb_vmss.id]
  destination_port_range                     = 22
}

resource "azurerm_network_security_rule" "graphdb_deny_inbound" {
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb_vmss.name

  name                       = "DenyInBound"
  description                = "Denies any other inbound traffic to GraphDB's subnet"
  priority                   = 4096
  direction                  = "Inbound"
  access                     = "Deny"
  protocol                   = "*"
  source_address_prefix      = "*"
  source_port_range          = "*"
  destination_address_prefix = "*"
  destination_port_range     = "*"
}

# Outbound rules

resource "azurerm_network_security_rule" "graphdb_allow_outbound_address" {
  count = length(var.graphdb_outbound_address_prefixes) == 0 ? 1 : 0

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb_vmss.name

  name                                  = "AllowOutBoundAddress"
  description                           = "Allows outbound connectivity from GraphDB VMs"
  priority                              = 100
  direction                             = "Outbound"
  access                                = "Allow"
  protocol                              = "*"
  source_application_security_group_ids = [azurerm_application_security_group.graphdb_vmss.id]
  source_port_range                     = "*"
  destination_address_prefix            = var.graphdb_outbound_address_prefix
  destination_port_range                = "*"
}

resource "azurerm_network_security_rule" "graphdb_allow_outbound_addresses" {
  count = length(var.graphdb_outbound_address_prefixes) > 0 ? 1 : 0

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb_vmss.name

  name                                  = "AllowOutBoundAddresses"
  description                           = "Allows outbound connectivity from GraphDB VMs"
  priority                              = 101
  direction                             = "Outbound"
  access                                = "Allow"
  protocol                              = "*"
  source_application_security_group_ids = [azurerm_application_security_group.graphdb_vmss.id]
  source_port_range                     = "*"
  destination_address_prefixes          = var.graphdb_outbound_address_prefixes
  destination_port_range                = "*"
}

resource "azurerm_network_security_rule" "graphdb_allow_internal_outbound" {
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb_vmss.name

  name                                       = "AllowInternalGraphDBOutBound"
  description                                = "Allows internal traffic between GraphDB nodes and proxies"
  priority                                   = 200
  direction                                  = "Outbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_application_security_group_ids      = [azurerm_application_security_group.graphdb_vmss.id]
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.graphdb_vmss.id]
  destination_port_ranges                    = ["7200", "7201", "7300", "7301"]
}

resource "azurerm_network_security_rule" "graphdb_deny_outbound" {
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb_vmss.name

  name                       = "DenyOutBound"
  description                = "Denies any other outbound traffic"
  priority                   = 4096
  direction                  = "Outbound"
  access                     = "Deny"
  protocol                   = "*"
  source_address_prefix      = "*"
  source_port_range          = "*"
  destination_address_prefix = "*"
  destination_port_range     = "*"
}
