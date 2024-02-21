#
# Log Analytics Workspace used by Application Insights and other monitoring resources
#
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-${var.resource_group_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.la_workspace_sku
  retention_in_days   = var.la_workspace_retention_in_days
  daily_quota_gb      = var.la_workspace_daily_quota_gb
}

#
# Application Insights
#
resource "azurerm_application_insights" "graphdb_insights" {
  name                                  = "appi-${var.resource_name_prefix}"
  location                              = var.location
  resource_group_name                   = var.resource_group_name
  application_type                      = var.appi_application_type
  retention_in_days                     = var.appi_retention_in_days
  workspace_id                          = azurerm_log_analytics_workspace.log_analytics_workspace.id
  internet_query_enabled                = var.appi_internet_query_enabled
  daily_data_cap_in_gb                  = var.appi_daily_data_cap_in_gb
  daily_data_cap_notifications_disabled = var.appi_daily_data_cap_notifications_disabled
  disable_ip_masking                    = var.appi_disable_ip_masking
}
