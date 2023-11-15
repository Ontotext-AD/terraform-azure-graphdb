# Create Network Security Group and rules
resource "azurerm_network_security_group" "graphdb" {
  name                = "${var.resource_name_prefix}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

resource "azurerm_network_security_rule" "graphdb-inbound-ssh" {
  count = var.source_ssh_blocks != null ? 1 : 0

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb.name

  name                       = "graphdb_ssh_inbound"
  description                = "Allow specified CIDRs SSH access to the GraphDB instances."
  priority                   = 900
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = 22
  source_address_prefixes    = var.source_ssh_blocks
  destination_address_prefix = var.graphdb_subnet_cidr
}

resource "azurerm_network_security_rule" "graphdb-proxies-inbound" {
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.graphdb.name

  name                       = "graphdb_proxies_inbound"
  description                = "Allow internet traffic to reach the GraphDB proxies"
  priority                   = 1000
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "7201"
  source_address_prefixes    = ["0.0.0.0/0"]
  destination_address_prefix = var.graphdb_subnet_cidr
}

locals {
  user_data_script = var.custom_user_data != null ? var.custom_user_data : templatefile("${path.module}/templates/entrypoint.sh.tpl", {
    graphdb_external_address_fqdn : var.graphdb_external_address_fqdn
    key_vault_name : var.key_vault_name
    disk_iops_read_write : var.disk_iops_read_write
    disk_mbps_read_write : var.disk_mbps_read_write
    disk_size_gb : var.disk_size_gb
    backup_schedule : var.backup_schedule
  })
}

# Create virtual machine scale set
resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = var.resource_group_name
  location            = var.location

  source_image_id = var.image_id
  user_data       = base64encode(local.user_data_script)

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  sku           = var.instance_type
  instances     = var.node_count
  zones         = var.zones
  zone_balance  = true
  upgrade_mode  = "Manual"
  overprovision = false

  computer_name_prefix = "${var.resource_name_prefix}-"
  admin_username       = "graphdb"

  network_interface {
    name                      = "${var.resource_name_prefix}-vmss-nic"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.graphdb.id

    ip_configuration {
      name                                         = "${var.resource_name_prefix}-ip-config"
      primary                                      = true
      subnet_id                                    = var.graphdb_subnet_id
      application_gateway_backend_address_pool_ids = var.application_gateway_backend_address_pool_ids
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    public_key = var.ssh_key
    username   = "graphdb"
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.rg-contributor-role]
}

resource "azurerm_role_definition" "managed_disk_manager" {
  name        = "ManagedDiskManager"
  scope       = var.resource_group_id
  description = "This is a custom role created via Terraform required for creating data disks for GraphDB"

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
      "Microsoft.Compute/virtualMachineScaleSets/read",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/write",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.Network/applicationGateways/backendAddressPools/join/action",
      "Microsoft.Network/networkSecurityGroups/join/action"
    ]
    not_actions = []
  }

  assignable_scopes = [
    var.resource_group_id
  ]
}

resource "azurerm_role_assignment" "rg-contributor-role" {
  principal_id         = var.identity_principal_id
  scope                = var.resource_group_id
  role_definition_name = "ManagedDiskManager"
  depends_on           = [azurerm_role_definition.managed_disk_manager]
}

resource "azurerm_role_definition" "backup_role" {
  name        = "ReadOnlyVMSSStorageRole"
  scope       = var.resource_group_id
  description = "This is a custom role created via Terraform required for creating backups in GraphDB"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachineScaleSets/read",
      "Microsoft.Storage/storageAccounts/read"
    ]
    not_actions = []
  }

  assignable_scopes = [
    var.resource_group_id
  ]
}

resource "azurerm_role_assignment" "rg-reader-role" {
  principal_id         = var.identity_principal_id
  scope                = var.resource_group_id
  role_definition_name = "ReadOnlyVMSSStorageRole"
  depends_on           = [azurerm_role_definition.backup_role]
}

