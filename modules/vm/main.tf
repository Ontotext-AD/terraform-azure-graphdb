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

  computer_name_prefix            = "${var.resource_name_prefix}-"
  admin_username                  = "graphdb"
  disable_password_authentication = true
  encryption_at_host_enabled      = var.encryption_at_host

  scale_in {
    # In case of re-balancing, remove the newest VM which might have not been IN-SYNC yet with the cluster
    rule = "NewestVM"
  }

  network_interface {
    name    = "${var.resource_name_prefix}-vmss-nic"
    primary = true

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

  depends_on = [azurerm_role_assignment.rg-contributor-role, azurerm_role_assignment.rg-reader-role]
}

resource "azurerm_monitor_autoscale_setting" "graphdb-autoscale-settings" {
  name                = "${var.resource_name_prefix}-vmss"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.graphdb.id

  profile {
    name = "${var.resource_name_prefix}-vmss-fixed"

    # We want to keep a tight count for 3 node quorum
    capacity {
      default = var.node_count
      maximum = var.node_count
      minimum = var.node_count
    }
  }

  tags = var.tags
}

resource "azurerm_role_definition" "managed_disk_manager" {
  name        = "${var.resource_name_prefix}-ManagedDiskManager"
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
  role_definition_name = "${var.resource_name_prefix}-ManagedDiskManager"
  depends_on           = [azurerm_role_definition.managed_disk_manager]
}

resource "azurerm_role_definition" "backup_role" {
  name        = "${var.resource_name_prefix}-ReadOnlyVMSSStorageRole"
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
  role_definition_name = "${var.resource_name_prefix}-ReadOnlyVMSSStorageRole"
  depends_on           = [azurerm_role_definition.backup_role]
}

