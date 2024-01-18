resource "azurerm_monitor_metric_alert" "disk_space_monitoring" {
  name                     = "${var.resource_group_name} Low data disk space"
  resource_group_name      = var.resource_group_name
  scopes                   = [var.log_analytics_workspace_id]
  description              = "Alert will be raised if free memory is bellow 10 percent"
  severity                 = var.disk_space_monitoring_severity
  enabled                  = true
  frequency                = var.disk_space_monitoring_frequency
  window_size              = var.disk_space_monitoring_window_size
  target_resource_location = var.location
  target_resource_type     = "Microsoft.OperationalInsights/workspaces"
  auto_mitigate            = var.disk_space_monitoring_auto_mitigate

  criteria {
    metric_namespace = "Microsoft.OperationalInsights/workspaces"
    metric_name      = "Average_% Free Space"
    aggregation      = "Minimum"
    operator         = "LessThanOrEqual"
    threshold        = var.disk_space_monitoring_threshold

    dimension {
      name     = "Computer"
      operator = "Include"
      values   = ["*"]
    }
    dimension {
      name     = "InstanceName"
      operator = "Include"
      values   = ["/var/opt/graphdb"]
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu_monitoring" {
  name                     = "${var.resource_group_name} High CPU usage"
  resource_group_name      = var.resource_group_name
  scopes                   = [var.vmss_resource_id]
  description              = "Alert will be raised if CPU usage is above 90 percent for 30 min"
  severity                 = var.cpu_monitoring_severity
  enabled                  = true
  frequency                = var.cpu_monitoring_frequency
  window_size              = var.cpu_monitoring_window_size
  target_resource_location = var.location
  target_resource_type     = "Microsoft.Compute/virtualMachineScaleSets"
  auto_mitigate            = var.cpu_monitoring_auto_mitigate

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_monitoring_threshold

    dimension {
      name     = "VMName"
      operator = "Include"
      values   = ["*"]
    }
  }
}

resource "azurerm_monitor_metric_alert" "memory_monitoring" {
  name                     = "${var.resource_group_name} Low memory"
  resource_group_name      = var.resource_group_name
  scopes                   = [var.vmss_resource_id]
  description              = "Alert will be raised if free memory drops below 4GB"
  severity                 = var.memory_monitoring_severity
  enabled                  = true
  frequency                = var.memory_monitoring_frequency
  window_size              = var.memory_monitoring_window_size
  target_resource_location = var.location
  target_resource_type     = "Microsoft.Compute/virtualMachineScaleSets"
  auto_mitigate            = var.memory_monitoring_auto_mitigate

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Available Memory Bytes"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.memory_monitoring_threshold
  }
}

resource "azurerm_monitor_activity_log_alert" "vm_health" {
  name                = "${var.resource_group_name} VM health"
  description         = "VMSS instances health alerts"
  resource_group_name = var.resource_group_name
  scopes              = [var.vmss_resource_id]

  criteria {
    resource_id    = var.vmss_resource_id
    operation_name = "Microsoft.Resourcehealth/healthevent/Activated/action"
    category       = "ResourceHealth"
    resource_type  = "Microsoft.Compute/virtualMachineScaleSets"
  }

}
