# Application config Audit log monitoring

resource "azurerm_monitor_diagnostic_setting" "application_config_diagnostic_settings" {
  name                       = "Application Config diagnostic settings"
  target_resource_id         = var.app_configuration_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_log {
    category = "Audit"
  }
}

# Key Vault Audit log monitoring

resource "azurerm_monitor_diagnostic_setting" "key_vault_diagnostic_settings" {
  count = var.create_key_vault_diagnostic_settings ? 1 : 0

  name                       = "Key Vault diagnostic settings"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_log {
    category = "AuditEvent"
  }
}
