output "log_analytics_workspace_id" {
  description = "Outputs log analytics workspace identifier"
  value = azurerm_log_analytics_workspace.log_analytics_workspace.id
}
