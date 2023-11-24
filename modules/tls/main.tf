resource "azurerm_user_assigned_identity" "graphdb-tls-certificate" {
  name                = "${var.resource_name_prefix}-tls"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# Azure AG requires this role to the be assigned to the Key Vault directly
resource "azurerm_role_assignment" "graphdb-tls-key-vault-secrets-reader" {
  principal_id         = azurerm_user_assigned_identity.graphdb-tls-certificate.principal_id
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_key_vault_certificate" "graphdb-tls-certificate" {
  name         = "${var.resource_name_prefix}-tls"
  key_vault_id = var.key_vault_id

  certificate {
    contents = var.tls_certificate
    password = var.tls_certificate_password
  }

  tags = var.tags
}
