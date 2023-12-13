resource "azurerm_user_assigned_identity" "graphdb_tls_certificate" {
  name                = "id-${var.resource_name_prefix}-tls"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Azure AG requires this role to the be assigned to the Key Vault directly
resource "azurerm_role_assignment" "graphdb_tls_key_vault_secrets_reader" {
  principal_id         = azurerm_user_assigned_identity.graphdb_tls_certificate.principal_id
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_key_vault_certificate" "graphdb_tls_certificate" {
  name         = "${var.resource_name_prefix}-tls"
  key_vault_id = var.key_vault_id

  certificate {
    contents = var.tls_certificate
    password = var.tls_certificate_password
  }
}
