resource "azurerm_user_assigned_identity" "graphdb_vmss" {
  name                = "id-${var.resource_name_prefix}-vmss"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Role assignments

resource "azurerm_role_assignment" "graphdb_vmss_key_vault_reader" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Reader"
}

resource "azurerm_role_assignment" "graphdb_vmss_app_config_reader" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.app_configuration_id
  role_definition_name = "Reader"
}

resource "azurerm_role_assignment" "graphdb_vmss_app_config_data_reader" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.app_configuration_id
  role_definition_name = "App Configuration Data Reader"
}

resource "azurerm_role_assignment" "graphdb_vmss_storage_contributor" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.backups_storage_container_id
  role_definition_name = "Storage Blob Data Contributor"
}

resource "azurerm_role_assignment" "graphdb_vmss_vm_contributor" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Contributor"
}

resource "azurerm_role_assignment" "graphdb_vmss_private_dns_contributor" {
  principal_id         = azurerm_user_assigned_identity.graphdb_vmss.principal_id
  scope                = var.private_dns_zone
  role_definition_name = "Private DNS Zone Contributor"
}

# VMSS

resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = "vmss-${var.resource_name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  source_image_id = var.image_id
  user_data       = base64encode(var.user_data_script)

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.graphdb_vmss.id]
  }

  sku           = var.instance_type
  instances     = var.node_count
  zones         = var.zones
  zone_balance  = true
  upgrade_mode  = "Manual"
  overprovision = false

  computer_name_prefix            = "${var.resource_name_prefix}-"
  admin_username                  = "graphdb"
  disable_password_authentication = true
  encryption_at_host_enabled      = var.encryption_at_host

  extension {
    name                       = "ConsulHealthExtension"
    publisher                  = "Microsoft.ManagedServices"
    type                       = "ApplicationHealthLinux"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = false

    settings = jsonencode({
      protocol    = "http"
      port        = 7200
      requestPath = "/rest/cluster/node/status"
    })
  }

  extension {
    name                 = "AzureMonitorLinuxAgent"
    publisher            = "Microsoft.Azure.Monitor"
    type                 = "AzureMonitorLinuxAgent"
    type_handler_version = "1.0"
  }

  automatic_instance_repair {
    enabled      = true
    grace_period = "PT10M"
  }

  scale_in {
    # In case of re-balancing, remove the newest VM which might have not been IN-SYNC yet with the cluster
    rule = "NewestVM"
  }

  network_interface {
    name    = "${var.resource_name_prefix}-vmss-nic"
    primary = true

    ip_configuration {
      name                                         = "${var.resource_name_prefix}-ip-config"
      primary                                      = true
      subnet_id                                    = var.graphdb_subnet_id
      application_gateway_backend_address_pool_ids = var.application_gateway_backend_address_pool_ids
      application_security_group_ids               = var.application_security_group_ids
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    public_key = var.ssh_key
    username   = "graphdb"
  }
}

resource "azurerm_monitor_autoscale_setting" "graphdb_auto_scale_settings" {
  name                = "${var.resource_name_prefix}-vmss"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.graphdb.id

  profile {
    name = "${var.resource_name_prefix}-vmss-fixed"

    # We want to keep a tight count for 3 node quorum
    capacity {
      default = var.node_count
      maximum = var.node_count
      minimum = var.node_count
    }
  }
}
