resource "random_password" "graphdb_cluster_token" {
  count   = var.graphdb_cluster_token != null ? 0 : 1
  length  = 16
  special = true
}

resource "random_password" "graphdb_password" {
  count  = var.graphdb_password != null ? 0 : 1
  length = 8
}

locals {
  graphdb_cluster_token = var.graphdb_cluster_token != null ? var.graphdb_cluster_token : random_password.graphdb_cluster_token[0].result
  graphdb_password      = var.graphdb_password != null ? var.graphdb_password : random_password.graphdb_password[0].result
}

resource "azurerm_app_configuration_key" "graphdb_license" {
  configuration_store_id = var.app_configuration_id
  key                    = var.graphdb_license_secret_name
  value                  = filebase64(var.graphdb_license_path)
  content_type           = "text/plain"
}

resource "azurerm_app_configuration_key" "graphdb_cluster_token" {
  configuration_store_id = var.app_configuration_id
  key                    = var.graphdb_cluster_token_name
  value                  = base64encode(local.graphdb_cluster_token)
  content_type           = "text/plain"
}

resource "azurerm_app_configuration_key" "graphdb_password" {
  configuration_store_id = var.app_configuration_id
  key                    = var.graphdb_password_secret_name
  value                  = base64encode(local.graphdb_password)
  content_type           = "text/plain"
}

resource "azurerm_app_configuration_key" "graphdb_properties" {
  count = var.graphdb_properties_path != null ? 1 : 0

  configuration_store_id = var.app_configuration_id
  key                    = var.graphdb_properties_secret_name
  value                  = filebase64(var.graphdb_properties_path)
  content_type           = "text/plain"
}

resource "azurerm_app_configuration_key" "graphdb_java_options" {
  count = var.graphdb_java_options != null ? 1 : 0

  configuration_store_id = var.app_configuration_id
  key                    = var.graphdb_java_options_secret_name
  value                  = base64encode(var.graphdb_java_options)
  content_type           = "text/plain"
}
