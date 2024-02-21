# Configure smart detection rules

resource "azurerm_application_insights_smart_detection_rule" "slow_server_response_time" {
  name                    = "Slow server response time"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = var.enable_smart_detection_rules
}

resource "azurerm_application_insights_smart_detection_rule" "degradation_server_response_time" {
  name                    = "Degradation in server response time"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = var.enable_smart_detection_rules
}

resource "azurerm_application_insights_smart_detection_rule" "rise_exception_volume" {
  name                    = "Abnormal rise in exception volume"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = var.enable_smart_detection_rules
}

resource "azurerm_application_insights_smart_detection_rule" "memory_leak_detection" {
  name                    = "Potential memory leak detected"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = var.enable_smart_detection_rules
}

resource "azurerm_application_insights_smart_detection_rule" "security_issue_detection" {
  name                    = "Potential security issue detected"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = var.enable_smart_detection_rules
}

resource "azurerm_application_insights_smart_detection_rule" "rise_daily_data_volume" {
  name                    = "Abnormal rise in daily data volume"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = var.enable_smart_detection_rules
}

# Disabling unneeded rules

resource "azurerm_application_insights_smart_detection_rule" "slow_page_load" {
  name                    = "Slow page load time"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = false
}

resource "azurerm_application_insights_smart_detection_rule" "long_dependency_duration" {
  name                    = "Long dependency duration"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = false
}

resource "azurerm_application_insights_smart_detection_rule" "dependency_duration_degradation" {
  name                    = "Degradation in dependency duration"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = false
}

resource "azurerm_application_insights_smart_detection_rule" "trace_severity_ratio_degradation" {
  name                    = "Degradation in trace severity ratio"
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  enabled                 = false
}
