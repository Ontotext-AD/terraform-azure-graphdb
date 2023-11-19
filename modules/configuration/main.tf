resource "random_password" "graphdb-cluster-token" {
  count   = var.graphdb_cluster_token != null ? 0 : 1
  length  = 16
  special = true
}

locals {
  graphdb_cluster_token = var.graphdb_cluster_token != null ? var.graphdb_cluster_token : random_password.graphdb-cluster-token[0].result
}

resource "azurerm_key_vault_secret" "graphdb-license" {
  key_vault_id = var.key_vault_id

  name  = var.graphdb_license_secret_name
  value = filebase64(var.graphdb_license_path)

  tags = var.tags
}

resource "azurerm_key_vault_secret" "graphdb-cluster-token" {
  key_vault_id = var.key_vault_id

  name  = var.graphdb_cluster_token_name
  value = base64encode(local.graphdb_cluster_token)

  tags = var.tags
}

resource "azurerm_key_vault_secret" "graphdb-properties" {
  count = var.graphdb_properties_path != null ? 1 : 0

  key_vault_id = var.key_vault_id

  name  = var.graphdb_properties_secret_name
  value = filebase64(var.graphdb_properties_path)

  tags = var.tags
}

resource "azurerm_key_vault_secret" "graphdb-java-options" {
  count = var.graphdb_java_options != null ? 1 : 0

  key_vault_id = var.key_vault_id

  name  = var.graphdb_java_options_secret_name
  value = base64encode(var.graphdb_java_options)

  tags = var.tags
}

# TODO: Cannot assign the secret resource as scope for some reason... it doesn't show in the console and it does not work in the VMs
# TODO: Not the right place for this to be here if we cannot give more granular access

# Give rights to the provided identity to be able to read it from the vault
resource "azurerm_role_assignment" "graphdb-license-reader" {
  principal_id         = var.identity_principal_id
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Reader"
}

# Give rights to the provided identity to actually get the secret value
resource "azurerm_role_assignment" "graphdb-license-secret-reader" {
  principal_id         = var.identity_principal_id
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
}
