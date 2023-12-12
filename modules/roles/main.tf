# Assign the identity to have read access to the key vault
resource "azurerm_role_assignment" "graphdb_vmss_key_vault_reader" {
  principal_id         = var.identity_principal_id
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Reader"
}

# Assign the identity to be able to upload GraphDB backups in the storage BLOB
resource "azurerm_role_assignment" "graphdb_backup" {
  principal_id         = var.identity_principal_id
  scope                = var.backups_storage_container_id
  role_definition_name = "Storage Blob Data Contributor"
}

resource "azurerm_role_assignment" "vm_contributor_role" {
  principal_id         = var.identity_principal_id
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Contributor"
}

resource "azurerm_role_assignment" "dns_zone_role_assignment" {
  principal_id         = var.identity_principal_id
  role_definition_name = "Private DNS Zone Contributor"
  scope                = var.private_dns_zone
}
