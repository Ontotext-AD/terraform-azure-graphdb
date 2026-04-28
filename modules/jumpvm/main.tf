#
# Jump VM — lightweight SSH proxy into the GraphDB VMSS subnet
#

resource "azurerm_subnet" "jumpvm" {
  name                 = "snet-${var.resource_name_prefix}-jumpvm"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.jump_subnet_address_prefixes
}

resource "azurerm_network_security_group" "jumpvm" {
  name                = "nsg-${var.resource_name_prefix}-jumpvm"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                       = "AllowSSHInBound"
    description                = "Allows SSH from management CIDR blocks"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = var.allowed_ssh_cidr_blocks
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "22"
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

  security_rule {
    name                         = "AllowSSHToGraphDB"
    description                  = "Allows SSH from Jump VM to GraphDB VMSS subnet"
    priority                     = 100
    direction                    = "Outbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_address_prefix        = "*"
    source_port_range            = "*"
    destination_address_prefixes = var.graphdb_subnet_address_prefixes
    destination_port_range       = "22"
  }

  security_rule {
    name                       = "AllowInternetOutBound"
    description                = "Allows outbound internet access for package installs and updates"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "Internet"
    destination_port_ranges    = ["80", "443"]
  }

  security_rule {
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
}

resource "azurerm_subnet_network_security_group_association" "jumpvm" {
  network_security_group_id = azurerm_network_security_group.jumpvm.id
  subnet_id                 = azurerm_subnet.jumpvm.id
}

resource "azurerm_public_ip" "jumpvm" {
  name                = "pip-${var.resource_name_prefix}-jumpvm"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "jumpvm" {
  name                = "nic-${var.resource_name_prefix}-jumpvm"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jumpvm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jumpvm.id
  }
}

resource "azurerm_linux_virtual_machine" "jumpvm" {
  name                = "vm-${var.resource_name_prefix}-jumpvm"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_sku
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.jumpvm.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}