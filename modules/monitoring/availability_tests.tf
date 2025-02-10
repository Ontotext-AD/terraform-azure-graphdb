# Availability tests

locals {
  web_test_url = var.node_count != 1 ? "https://${var.graphdb_external_address_fqdn}/rest/cluster/node/status" : "https://${var.graphdb_external_address_fqdn}/protocol"
}

resource "azurerm_application_insights_standard_web_test" "at-cluster-health" {
  count = var.appi_web_test_availability_enabled && !var.gateway_enable_private_access ? 1 : 0

  name                    = "at-${var.resource_name_prefix}-cluster-health"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.graphdb_insights.id
  geo_locations           = var.web_test_geo_locations
  frequency               = var.web_test_frequency
  timeout                 = var.web_test_timeout

  request {
    url = local.web_test_url
  }

  validation_rules {
    expected_status_code = var.web_test_availability_expected_status_code
    ssl_check_enabled    = var.web_test_ssl_check_enabled

    # Content match will not be enabled if a single node is deployed
    dynamic "content" {
      for_each = var.node_count > 1 ? [1] : []
      content {
        content_match      = var.web_test_availability_content_match
        pass_if_text_found = true
        ignore_case        = true
      }
    }
  }
}
