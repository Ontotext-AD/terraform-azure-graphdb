# Action group for the alerts

resource "azurerm_monitor_action_group" "notification_group" {
  name                = "ag-${var.resource_name_prefix}-notifications"
  resource_group_name = var.resource_group_name
  short_name          = "Notification"

  dynamic "email_receiver" {
    for_each = var.ag_notifications_email_list
    content {
      name          = "email notification ${email_receiver.value}"
      email_address = email_receiver.value
    }
  }

  dynamic "azure_app_push_receiver" {
    for_each = var.ag_notifications_email_list
    content {
      name          = "push notification ${azure_app_push_receiver.value}"
      email_address = azure_app_push_receiver.value
    }
  }
}

# Role assignments

resource "azurerm_role_assignment" "monitoring_reader" {
  principal_id = var.monitor_reader_principal_id
  # TODO test this out, not sure if this is the proper scope
  scope                = azurerm_application_insights.graphdb_insights.id
  role_definition_name = "Monitoring Reader"
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
