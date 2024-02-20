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
