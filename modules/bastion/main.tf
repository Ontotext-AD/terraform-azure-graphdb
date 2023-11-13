data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "graphdb" {
  name = var.virtual_network_name
  resource_group_name = data.azurerm_resource_group.graphdb.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = data.azurerm_resource_group.graphdb.name
  virtual_network_name = data.azurerm_virtual_network.graphdb.name
  address_prefixes     = ["10.0.3.0/27"]
}

resource "azurerm_public_ip" "publicIP" {
  name                = "${var.resource_name_prefix}_bastion_publicIP"
  location            = data.azurerm_resource_group.graphdb.location
  resource_group_name = data.azurerm_resource_group.graphdb.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastionHost" {
  name                = "${var.resource_name_prefix}_bastion"
  location            = data.azurerm_resource_group.graphdb.location
  resource_group_name = data.azurerm_resource_group.graphdb.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.subnet.id
    public_ip_address_id = azurerm_public_ip.publicIP.id
  }
}
