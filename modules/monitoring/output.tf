output "la_workspace_id" {
  description = "Outputs log analytics workspace identifier"
  value       = azurerm_log_analytics_workspace.log_analytics_workspace.id
}

output "appi_connection_string" {
  description = "Outputs the connection string for Application Insights"
  value       = azurerm_application_insights.graphdb_insights.connection_string
}
