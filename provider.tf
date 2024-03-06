provider "azurerm" {
  features {
    managed_disk {
      expand_without_downtime = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    app_configuration {
      purge_soft_delete_on_destroy = false
    }
  }
  # Required when shared_access_key_enabled is false
  storage_use_azuread = true
}
