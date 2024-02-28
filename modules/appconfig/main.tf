resource "random_string" "app_config_name_prefix" {
  length  = 6
  lower   = true
  numeric = false
  special = false
  upper   = false
}

locals {
  # Creates an unique app configuration name to max of 50 characters
  app_configuration_name = "appcs-${substr(var.resource_name_prefix, 0, 37)}-${random_string.app_config_name_prefix.result}"
}

resource "azurerm_app_configuration" "graphdb" {
  name                = local.app_configuration_name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku = "standard"

  # Note: Enabled until we add a private endpoint
  public_network_access      = "Enabled"
  local_auth_enabled         = false
  purge_protection_enabled   = var.app_config_enable_purge_protection
  soft_delete_retention_days = var.app_config_retention_days
}

resource "azurerm_monitor_diagnostic_setting" "application_config_diagnostic_settings" {
  name                       = "Application Config diagnostic settings"
  target_resource_id         = azurerm_app_configuration.graphdb.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "Audit"
  }
}

resource "azurerm_role_assignment" "app_config_data_owner" {
  principal_id         = var.admin_security_principle_id
  scope                = azurerm_app_configuration.graphdb.id
  role_definition_name = "App Configuration Data Owner"
}
