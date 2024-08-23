#
# Identity and role assignments
#

resource "azurerm_user_assigned_identity" "graphdb_vmss" {
  name                = "id-${var.resource_name_prefix}-vmss"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Required by the 01_wait_resources.sh.tpl template
resource "azurerm_role_assignment" "graphdb_rg_reader" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.resource_group_id
  role_definition_name = "Reader"
}

resource "azurerm_role_assignment" "graphdb_vmss_app_config_data_reader" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.app_configuration_id
  role_definition_name = "App Configuration Data Reader"
}

resource "azurerm_role_assignment" "graphdb_vmss_storage_contributor" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.backup_storage_container_id
  role_definition_name = "Storage Blob Data Contributor"
}

resource "azurerm_role_assignment" "graphdb_vmss_vm_contributor" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Contributor"
}

resource "azurerm_role_assignment" "graphdb_vmss_private_dns_contributor" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = azurerm_private_dns_zone.graphdb.id
  role_definition_name = "Private DNS Zone Contributor"
}
