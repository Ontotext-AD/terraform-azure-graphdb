resource "random_password" "graphdb_cluster_token" {
  count   = var.graphdb_cluster_token != null ? 0 : 1
  length  = 16
  special = true
}

resource "random_password" "graphdb_password" {
  count  = var.graphdb_cluster_token != null ? 0 : 1
  length = 8
}

locals {
  graphdb_cluster_token = var.graphdb_cluster_token != null ? var.graphdb_cluster_token : random_password.graphdb_cluster_token[0].result
  graphdb_password      = var.graphdb_password != null ? var.graphdb_password : random_password.graphdb_password[0].result
}

resource "azurerm_key_vault_secret" "graphdb_license" {
  key_vault_id = var.key_vault_id

  name         = var.graphdb_license_secret_name
  value        = filebase64(var.graphdb_license_path)
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "graphdb_cluster_token" {
  key_vault_id = var.key_vault_id

  name         = var.graphdb_cluster_token_name
  value        = base64encode(local.graphdb_cluster_token)
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "graphdb_password" {
  key_vault_id = var.key_vault_id

  name         = var.graphdb_password_secret_name
  value        = base64encode(local.graphdb_password)
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "graphdb_properties" {
  count = var.graphdb_properties_path != null ? 1 : 0

  key_vault_id = var.key_vault_id

  name         = var.graphdb_properties_secret_name
  value        = filebase64(var.graphdb_properties_path)
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "graphdb_java_options" {
  count = var.graphdb_java_options != null ? 1 : 0

  key_vault_id = var.key_vault_id

  name         = var.graphdb_java_options_secret_name
  value        = base64encode(var.graphdb_java_options)
  content_type = "text/plain"
}

resource "azurerm_role_assignment" "graphdb_license_secret_reader" {
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb_license.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_role_assignment" "graphdb_cluster_token_secret_reader" {
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb_cluster_token.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_role_assignment" "graphdb_java_options_secret_reader" {
  count                = var.graphdb_java_options != null ? 1 : 0
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb_java_options[0].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_role_assignment" "graphdb_password_secret_reader" {
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb_password.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_role_assignment" "graphdb_properties_secret_reader" {
  count                = var.graphdb_properties_path != null ? 1 : 0
  principal_id         = var.identity_principal_id
  scope                = azurerm_key_vault_secret.graphdb_properties[0].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
}
