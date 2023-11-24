resource "random_password" "graphdb-cluster-token" {
  count   = var.graphdb_cluster_token != null ? 0 : 1
  length  = 16
  special = true
}

resource "random_password" "graphdb-password" {
  count  = var.graphdb_cluster_token != null ? 0 : 1
  length = 8
}

locals {
  graphdb_cluster_token = var.graphdb_cluster_token != null ? var.graphdb_cluster_token : random_password.graphdb-cluster-token[0].result
  graphdb_password      = var.graphdb_password != null ? var.graphdb_password : random_password.graphdb-password[0].result
}

resource "azurerm_key_vault_secret" "graphdb-license" {
  key_vault_id = var.key_vault_id

  name         = var.graphdb_license_secret_name
  value        = filebase64(var.graphdb_license_path)
  content_type = "text/plain"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "graphdb-cluster-token" {
  key_vault_id = var.key_vault_id

  name         = var.graphdb_cluster_token_name
  value        = base64encode(local.graphdb_cluster_token)
  content_type = "text/plain"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "graphdb-password" {
  key_vault_id = var.key_vault_id

  name         = var.graphdb_password_secret_name
  value        = base64encode(local.graphdb_password)
  content_type = "text/plain"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "graphdb-properties" {
  count = var.graphdb_properties_path != null ? 1 : 0

  key_vault_id = var.key_vault_id

  name         = var.graphdb_properties_secret_name
  value        = filebase64(var.graphdb_properties_path)
  content_type = "text/plain"

  tags = var.tags
}

resource "azurerm_key_vault_secret" "graphdb-java-options" {
  count = var.graphdb_java_options != null ? 1 : 0

  key_vault_id = var.key_vault_id

  name         = var.graphdb_java_options_secret_name
  value        = base64encode(var.graphdb_java_options)
  content_type = "text/plain"

  tags = var.tags
}

resource "azurerm_role_assignment" "graphdb-license-secret-reader" {
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb-license.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_role_assignment" "graphdb-cluster-token-secret-reader" {
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb-cluster-token.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_role_assignment" "graphdb-java-options-secret-reader" {
  count                = var.graphdb_java_options != null ? 1 : 0
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb-java-options[0].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_role_assignment" "graphdb-password-secret-reader" {
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb-password.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_role_assignment" "graphdb-properties-secret-reader" {
  count                = var.graphdb_properties_path != null ? 1 : 0
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb-properties[0].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}
