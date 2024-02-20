resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-${var.resource_group_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.la_workspace_sku
  retention_in_days   = var.la_workspace_retention_in_days
  daily_quota_gb      = var.la_workspace_daily_quota_gb
}

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

resource "azurerm_monitor_action_group" "notification_group" {
  name                = "ag-${var.resource_name_prefix}-notifications"
  resource_group_name = var.resource_group_name
  short_name          = "Notification"

  arm_role_receiver {
    name                    = "owner notifications"
    role_id                 = var.ag_arm_role_receiver_role_id
    use_common_alert_schema = true
  }

  dynamic "azure_app_push_receiver" {
    for_each = var.ag_push_notification_accounts
    content {
      name          = "push notification ${azure_app_push_receiver.value}"
      email_address = azure_app_push_receiver.value
    }
  }
}

# Role assignments
# This is required for the smart detection action group.
resource "azurerm_role_assignment" "monitoring_reader" {
  principal_id = var.monitor_reader_principal_id
  # TODO test this out, not sure if this is the proper scope
  scope                = azurerm_application_insights.graphdb_insights.id
  role_definition_name = "Monitoring Reader"
}

# Smart detection rules

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

# Availability tests
resource "azurerm_application_insights_standard_web_test" "at-cluster-health" {
  enabled = var.appi_web_test_availability_enabled

  name                    = "at-${var.resource_name_prefix}-cluster-health"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  geo_locations           = var.web_test_geo_locations
  frequency               = var.web_test_frequency
  timeout                 = var.web_test_timeout

  request {
    url = "https://${var.web_test_availability_request_url}/rest/cluster/node/status"
  }

  validation_rules {
    expected_status_code = var.web_test_availability_expected_status_code
    ssl_check_enabled    = var.web_test_ssl_check_enabled

    content {
      content_match      = var.web_test_availability_content_match
      pass_if_text_found = true
      ignore_case        = true
    }
  }
}

# Alerts
resource "azurerm_monitor_metric_alert" "availability_alert" {
  enabled = var.appi_web_test_availability_enabled

  name                = "al-${var.resource_name_prefix}-availability"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_insights.graphdb_insights.id]
  description         = "Alarm will trigger if availability goes beneath 100"
  severity            = 0

  frequency                = "PT1M"
  window_size              = "PT5M"
  target_resource_location = var.location
  target_resource_type     = "microsoft.insights/components"
  auto_mitigate            = true

  criteria {
    metric_namespace       = "microsoft.insights/components"
    metric_name            = "availabilityResults/availabilityPercentage"
    aggregation            = "Average"
    operator               = "LessThan"
    threshold              = 100
    skip_metric_validation = true
  }
  action {
    action_group_id = azurerm_monitor_action_group.notification_group.id
  }
}

resource "azurerm_monitor_metric_alert" "low_memory_warning" {
  enabled = var.enable_alerts

  name                     = "al-${var.resource_name_prefix}-low-memory"
  resource_group_name      = var.resource_group_name
  scopes                   = [azurerm_application_insights.graphdb_insights.id]
  description              = "Alarm will trigger if Max Heap Memory Used is over the threshold"
  severity                 = 2
  frequency                = "PT1M"
  window_size              = "PT5M"
  target_resource_location = var.location
  target_resource_type     = "microsoft.insights/components"
  auto_mitigate            = true

  criteria {
    metric_namespace       = "Azure.ApplicationInsights"
    metric_name            = "% Of Max Heap Memory Used"
    aggregation            = "Average"
    operator               = "GreaterThan"
    threshold              = var.al_low_memory_warning_threshold
    skip_metric_validation = true
  }
  action {
    action_group_id = azurerm_monitor_action_group.notification_group.id
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "replication-warning" {
  enabled = var.enable_alerts

  name                = "al-${var.resource_name_prefix}-replication-warning"
  description         = "Alert will be triggered if snapshot replication is detected"
  resource_group_name = var.resource_group_name
  location            = var.location

  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  evaluation_frequency             = "PT10M"
  window_duration                  = "PT10M"
  scopes                           = [azurerm_application_insights.graphdb_insights.id]
  severity                         = 1

  criteria {
    query = <<-QUERY
      traces
        | where message has "Attempting to recover through snapshot replication"
      QUERY

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  skip_query_validation = true
  action {
    action_groups = [azurerm_monitor_action_group.notification_group.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "low-disk-space" {
  enabled = var.enable_alerts

  name                = "al-${var.resource_group_name}-low-disk-space"
  description         = "Alert will be triggered if low disk space message is detected"
  resource_group_name = var.resource_group_name
  location            = var.location

  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  evaluation_frequency             = "PT5M"
  window_duration                  = "PT10M"
  scopes                           = [azurerm_application_insights.graphdb_insights.id]
  severity                         = 1

  criteria {
    query = <<-QUERY
      traces
        | where message has "low disk space"
        or message has "The system is running out of disk space"
      QUERY

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  skip_query_validation = true
  action {
    action_groups = [azurerm_monitor_action_group.notification_group.id]
  }
}
