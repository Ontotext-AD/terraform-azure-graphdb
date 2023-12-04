data "azurerm_client_config" "current" {
}

resource "random_string" "vault_name_suffix" {
  length  = 10
  lower   = true
  numeric = false
  special = false
  upper   = false
}

locals {
  vault_name = "${var.resource_name_prefix}-${random_string.vault_name_suffix.result}"
}

resource "azurerm_key_vault" "graphdb" {
  name                = local.vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = var.key_vault_enable_purge_protection
  soft_delete_retention_days = var.key_vault_retention_days

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    virtual_network_subnet_ids = var.nacl_subnet_ids
    ip_rules                   = var.nacl_ip_rules
  }

  tags = var.tags
}

# TODO: This feels like a hack that could be avoided by using an authorized service principle or managed identity when deploying with TF
# Add vault data permissions to the current client that is executing this Terraform script
resource "azurerm_role_assignment" "graphdb_key_vault_manager" {
  principal_id         = data.azurerm_client_config.current.object_id
  scope                = azurerm_key_vault.graphdb.id
  role_definition_name = "Key Vault Administrator"
}
