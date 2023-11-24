resource "azurerm_subnet" "graphdb-bastion-subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.bastion_subnet_address_prefix
}

resource "azurerm_public_ip" "graphdb-bastion-public-ip" {
  name                = "${var.resource_name_prefix}_bastion_publicIP"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "graphdb-bastion-host" {
  name                = "${var.resource_name_prefix}_bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tunneling_enabled   = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.graphdb-bastion-subnet.id
    public_ip_address_id = azurerm_public_ip.graphdb-bastion-public-ip.id
  }

  tags = var.tags
}
