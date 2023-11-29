# Assign the identity to have read access to the key vault
resource "azurerm_role_assignment" "graphdb-vmss-key-vault-reader" {
  principal_id         = var.identity_principal_id
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Reader"
}

# Assign the identity to be able to upload GraphDB backups in the storage BLOB
resource "azurerm_role_assignment" "graphdb-backup" {
  principal_id         = var.identity_principal_id
  scope                = var.backups_storage_container_id
  role_definition_name = "Storage Blob Data Contributor"
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
  role_definition_name = azurerm_role_definition.managed_disk_manager.name

  depends_on = [azurerm_role_definition.managed_disk_manager]
}

resource "azurerm_role_assignment" "dns_zone_role_assignment" {
  principal_id         = var.identity_principal_id
  role_definition_name = "Private DNS Zone Contributor"
  scope                = var.private_dns_zone
}
