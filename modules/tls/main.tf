data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}

data "azurerm_key_vault" "graphdb" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
}

locals {
  resource_group = data.azurerm_resource_group.graphdb.name
  location       = data.azurerm_resource_group.graphdb.location
}

resource "azurerm_user_assigned_identity" "graphdb-tls-certificate" {
  name                = "${var.resource_name_prefix}-tls"
  resource_group_name = local.resource_group
  location            = local.location

  tags = var.tags
}

# TODO: probably have to add Key Vault Reader as well

resource "azurerm_role_assignment" "graphdb-tls-certificate-reader" {
  principal_id         = azurerm_user_assigned_identity.graphdb-tls-certificate.principal_id
  scope                = data.azurerm_key_vault.graphdb.id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_key_vault_certificate" "graphdb-tls-certificate" {
  name         = "${var.resource_name_prefix}-tls"
  key_vault_id = data.azurerm_key_vault.graphdb.id

  certificate {
    contents = var.tls_certificate
    password = var.tls_certificate_password
  }
}
