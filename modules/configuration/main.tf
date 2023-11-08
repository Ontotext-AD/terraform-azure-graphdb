data "azurerm_user_assigned_identity" "graphdb-instances" {
  name                = var.identity_name
  resource_group_name = var.resource_group_name
}

data "azurerm_key_vault" "graphdb" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_key_vault_secret" "graphdb-license" {
  key_vault_id = data.azurerm_key_vault.graphdb.id

  name  = var.graphdb_license_secret_name
  value = filebase64(var.graphdb_license_path)

  tags = var.tags
}

# TODO: Cannot assign the secret resource as scope for some reason... it doesn't show in the console and it does not work in the VMs

# Give rights to the provided identity to be able to read it from the vault
resource "azurerm_role_assignment" "graphdb-license-reader" {
  principal_id         = data.azurerm_user_assigned_identity.graphdb-instances.principal_id
  scope                = data.azurerm_key_vault.graphdb.id
  role_definition_name = "Reader"
}

# Give rights to the provided identity to actually get the secret value
resource "azurerm_role_assignment" "graphdb-license-secret-reader" {
  principal_id         = data.azurerm_user_assigned_identity.graphdb-instances.principal_id
  scope                = data.azurerm_key_vault.graphdb.id
  role_definition_name = "Key Vault Secrets User"
}
