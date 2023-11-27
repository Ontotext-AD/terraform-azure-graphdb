resource "random_string" "storage_account_name_suffix" {
  length  = 6
  lower   = true
  numeric = false
  special = false
  upper   = false
}

locals {
  # Storage account names have very specific naming restrictions

  # Remove all non alphanumeric characters
  sanitized = replace(var.resource_name_prefix, "/[^a-zA-Z0-9]/", "")

  # Trim down to 18 characters to allow the random suffix of 6
  trimmed = lower(substr(local.sanitized, 0, 18))

  # Create storage account name with unique suffix
  storage_account_name = "${local.trimmed}${random_string.storage_account_name_suffix.result}"
}

# Create an Azure Storage Account for backups
resource "azurerm_storage_account" "graphdb-backup" {
  name                      = local.storage_account_name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  account_tier              = var.storage_account_tier
  account_replication_type  = var.storage_account_replication_type
  enable_https_traffic_only = true
  min_tls_version           = "TLS1_2"

  tags = var.tags
}

# Create an Azure Storage container
resource "azurerm_storage_container" "graphdb-backup" {
  name                  = "${var.resource_name_prefix}-backup"
  storage_account_name  = azurerm_storage_account.graphdb-backup.name
  container_access_type = "private"
}

# Create an Azure Storage blob
resource "azurerm_storage_blob" "graphdb-backup" {
  name                   = "${var.resource_name_prefix}-backup"
  type                   = "Block"
  storage_account_name   = azurerm_storage_account.graphdb-backup.name
  storage_container_name = azurerm_storage_container.graphdb-backup.name
}

resource "azurerm_role_assignment" "graphdb-backup" {
  principal_id         = var.identity_principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.graphdb-backup.id
}

resource "azurerm_storage_management_policy" "graphdb-backup-retention" {
  storage_account_id = azurerm_storage_account.graphdb-backup.id

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
