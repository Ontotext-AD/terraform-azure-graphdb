locals {
  gdb_main_log_table_name        = "gdb_main_log_CL"
  log_analytics_destination_name = "gdb-destination-log"
  performance_counter_name       = "gdb-perfcounter"
}

resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "log-${var.resource_group_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.workspace_sku
  retention_in_days   = var.workspace_retention_in_days
}

resource "azurerm_monitor_data_collection_endpoint" "data_collection_endpoint" {
  name                          = "dce-${var.resource_group_name}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  kind                          = var.data_collection_kind
  public_network_access_enabled = var.dce_public_network_access_enabled
  description                   = "monitor_data_collection_endpoint ${var.resource_group_name}"
}

resource "azurerm_monitor_data_collection_rule_association" "DCE_association" {
  target_resource_id          = var.vmss_resource_id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.data_collection_endpoint.id
  description                 = "Associates DCE to the VMSS"
}

resource "azurerm_monitor_data_collection_rule" "data_collection_rule" {
  name                        = "dcr-${var.resource_group_name}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.data_collection_endpoint.id
  kind                        = var.data_collection_kind

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
      name                  = local.log_analytics_destination_name
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog", "Microsoft-Perf", "Microsoft-InsightsMetrics"]
    destinations = [local.log_analytics_destination_name]
  }

  data_flow {
    streams       = ["Custom-${azapi_resource.main_gdb_log_table.name}"]
    destinations  = [local.log_analytics_destination_name]
    output_stream = "Custom-${azapi_resource.main_gdb_log_table.name}"
    transform_kql = "source"
  }

  data_sources {
    syslog {
      facility_names = [
        "daemon",
        "kern",
        "syslog"
      ]
      log_levels = [
        "Error",
        "Critical",
        "Alert",
        "Emergency"
      ]
      name    = "gdb-datasource-syslog"
      streams = ["Microsoft-Syslog"]
    }

    log_file {
      name          = local.gdb_main_log_table_name
      format        = "text"
      streams       = ["Custom-${azapi_resource.main_gdb_log_table.name}"]
      file_patterns = ["/var/opt/graphdb/node/logs/main.log"]
      settings {
        text {
          record_start_timestamp_format = "ISO 8601"
        }
      }
    }

    performance_counter {
      streams                       = ["Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = var.performance_counter_sampling_frequency_in_seconds

      counter_specifiers = [
        "\\VmInsights\\DetailedMetrics"
      ]
      name = "VMInsightsPerfCounters"
    }

    # TODO Review and remove unneeded specifiers
    performance_counter {
      streams                       = ["Microsoft-Perf", "Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = var.performance_counter_sampling_frequency_in_seconds

      counter_specifiers = [
        "Processor(*)\\% Processor Time",
        "Processor(*)\\% IO Wait Time",
        "Memory(*)\\% Available Memory",
        "Memory(*)\\% Used Memory",
        "Logical Disk(*)\\% Free Space",
        "Logical Disk(*)\\% Used Space",
        "System(*)\\Uptime"
      ]
      name = local.performance_counter_name
    }
  }

  stream_declaration {
    stream_name = "Custom-${azapi_resource.main_gdb_log_table.name}"
    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "RawData"
      type = "string"
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "DCR_association" {
  name                    = "dcra-${var.resource_group_name}"
  target_resource_id      = var.vmss_resource_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.data_collection_rule.id
  description             = "Associates DCR to the VMSS"
}

# We need to use the azapi as terraform does not have a resource to create tables.
resource "azapi_resource" "main_gdb_log_table" {
  name      = local.gdb_main_log_table_name
  parent_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"

  body = jsonencode(
    {
      "properties" : {
        "schema" : {
          "name" : local.gdb_main_log_table_name,
          "columns" : [
            {
              "name" : "TimeGenerated",
              "type" : "datetime",
              "description" : "The time at which the data was generated"
            },
            {
              "name" : "RawData",
              "type" : "string"
              "description" : "Raw GraphDB log data"
            }
          ]
        },
        "retentionInDays" : var.main_log_table_retentionInDays,
        "totalRetentionInDays" : var.main_log_table_totalRetentionInDays,
        "plan" : var.custom_table_plan
      }
    }
  )
}
