# Create an Azure Storage Account for backups
resource "azurerm_storage_account" "backup" {
  name                      = "${var.resource_name_prefix}2graphdbbackup"
  resource_group_name       = var.resource_group_name
  location                  = var.location
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  enable_https_traffic_only = true
  min_tls_version           = "TLS1_2"

  tags = var.tags
}

# Create an Azure Storage container
resource "azurerm_storage_container" "backup" {
  name                  = "${var.resource_name_prefix}-backup"
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
}

# Create an Azure Storage blob
resource "azurerm_storage_blob" "backup" {
  name                   = "${var.resource_name_prefix}-backup"
  type                   = "Block"
  storage_account_name   = azurerm_storage_account.backup.name
  storage_container_name = azurerm_storage_container.backup.name
}

resource "azurerm_role_assignment" "backup" {
  principal_id         = var.identity_principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.backup.id
}

resource "azurerm_storage_management_policy" "retention" {
  storage_account_id = azurerm_storage_account.backup.id

  rule {
    enabled = true
    name    = "31DayRetention"
    filters {
      blob_types = ["blockBlob", "appendBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 31
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 31
      }
      version {
        delete_after_days_since_creation = 31
      }
    }
  }
}
