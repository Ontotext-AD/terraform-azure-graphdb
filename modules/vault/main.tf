data "azurerm_client_config" "current" {
}

resource "random_string" "vault_name_suffix" {
  length  = 6
  lower   = true
  numeric = false
  special = false
  upper   = false
}

locals {
  # Trim down to 13 characters and append the prefix and suffix to a maximum of 23 characters.
  vault_name = "kv-${substr(var.resource_name_prefix, 0, 13)}-${random_string.vault_name_suffix.result}"
}

resource "azurerm_key_vault" "graphdb" {
  name                = local.vault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = var.key_vault_enable_purge_protection
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    virtual_network_subnet_ids = var.nacl_subnet_ids
    ip_rules                   = var.nacl_ip_rules
  }
}

resource "azurerm_role_assignment" "graphdb_key_vault_manager" {
  principal_id         = var.admin_security_principle_id
  scope                = azurerm_key_vault.graphdb.id
  role_definition_name = "Key Vault Administrator"
}

resource "azurerm_monitor_diagnostic_setting" "key_vault_diagnostic_settings" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "Key Vault diagnostic settings"
  target_resource_id         = azurerm_key_vault.graphdb.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }
}
