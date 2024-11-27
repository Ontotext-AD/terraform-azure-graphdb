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
  trimmed = lower(substr("st${local.sanitized}", 0, 18))

  # Create storage account name with unique suffix and a maximum of 24 characters
  storage_account_name = "${local.trimmed}${random_string.storage_account_name_suffix.result}"
}

# Create an Azure Storage Account for backups
resource "azurerm_storage_account" "graphdb_backup" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind                      = var.storage_account_kind
  account_tier                      = var.storage_account_tier
  account_replication_type          = var.storage_account_replication_type
  enable_https_traffic_only         = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  allowed_copy_scope                = var.storage_account_allowed_copy_scope

  blob_properties {
    container_delete_retention_policy {
      days = var.storage_container_soft_delete_retention_policy
    }
    delete_retention_policy {
      days = var.storage_blob_soft_delete_retention_policy
    }
    last_access_time_enabled      = true
    change_feed_enabled           = true
    change_feed_retention_in_days = var.storage_blobs_max_days_since_creation
  }

  network_rules {
    bypass                     = ["AzureServices"]
    default_action             = "Deny"
    virtual_network_subnet_ids = var.nacl_subnet_ids
    ip_rules                   = var.nacl_ip_rules
  }
}

# Create an Azure Storage container
resource "azurerm_storage_container" "graphdb_backup" {
  name                  = "${var.resource_name_prefix}-backup"
  storage_account_name  = azurerm_storage_account.graphdb_backup.name
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "graphdb_backup_retention" {
  storage_account_id = azurerm_storage_account.graphdb_backup.id

  rule {
    name    = "31DayRetention"
    enabled = true
    filters {
      blob_types = ["blockBlob", "appendBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = var.storage_blobs_max_days_since_creation
      }
      snapshot {
        delete_after_days_since_creation_greater_than = var.storage_blobs_max_days_since_creation
      }
      version {
        delete_after_days_since_creation = var.storage_blobs_max_days_since_creation
      }
    }
  }

  # Create a rule to change tiers to cool after specific days since creation
  rule {
    name    = "HotToCoolTransitionRule"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_creation_greater_than = var.storage_account_retention_hot_to_cool
      }
      snapshot {
        tier_to_cold_after_days_since_creation_greater_than = var.storage_account_retention_hot_to_cool
      }
      version {
        change_tier_to_cool_after_days_since_creation = var.storage_account_retention_hot_to_cool
      }
    }
  }
}
