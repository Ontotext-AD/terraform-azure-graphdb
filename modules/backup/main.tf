data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}
data "azurerm_user_assigned_identity" "graphdb-instances" {
  name                = var.identity_name
  resource_group_name = var.resource_group_name
}
locals {
  resource_group = data.azurerm_resource_group.graphdb.name
  location       = data.azurerm_resource_group.graphdb.location
}

# Create an Azure Storage Account for backups
resource "azurerm_storage_account" "backup" {
  name                      = "${var.resource_name_prefix}-graphdb-backup"
  resource_group_name       = local.resource_group
  location                  = local.location
  account_tier              = var.account_tier
  account_replication_type  = var.account_replication_type
  enable_https_traffic_only = true

  tags = var.tags
}

# Create an Azure Storage container
resource "azurerm_storage_container" "backup" {
  name                  = "${var.resource_name_prefix}-graphdb-backup"
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
}

# Create an Azure Storage blob
resource "azurerm_storage_blob" "backup" {
  name                   = "${var.resource_name_prefix}-graphdb-backup"
  type                   = "Block"
  storage_account_name   = azurerm_storage_account.backup.name
  storage_container_name = azurerm_storage_container.backup.name
}

resource "azurerm_role_assignment" "backup" {
  principal_id         = data.azurerm_user_assigned_identity.graphdb-instances.principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_container.backup.id
}