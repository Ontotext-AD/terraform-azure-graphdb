#
# Linux VMs scale set for GraphDB
#

resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = "vmss-${var.resource_name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  source_image_id = var.graphdb_image_id

  dynamic "source_image_reference" {
    for_each = var.graphdb_image_id == null ? [1] : []
    content {
      offer     = "graphdb-ee"
      publisher = "ontotextad1692361256062"
      sku       = var.graphdb_sku
      version   = var.graphdb_version
    }
  }

  dynamic "plan" {
    for_each = var.graphdb_image_id == null ? [1] : []
    content {
      name      = "graphdb-byol"
      product   = "graphdb-ee"
      publisher = "ontotextad1692361256062"
    }
  }

  user_data = data.cloudinit_config.entrypoint.rendered

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

  # Explicitly setting instance repair to false.
  # Re-creating a GraphDB instance would not solve any issues in most cases.
  automatic_instance_repair {
    enabled = false
  }

  scale_in {
    # In case of re-balancing, remove the newest VM which might have not been IN-SYNC yet with the cluster
    rule = "NewestVM"
  }

  network_interface {
    name    = "nic-${var.resource_name_prefix}-vmss"
    primary = true

    ip_configuration {
      name                                         = "${var.resource_name_prefix}-ip-config"
      primary                                      = true
      subnet_id                                    = var.graphdb_subnet_id
      application_gateway_backend_address_pool_ids = var.application_gateway_backend_address_pool_ids
      application_security_group_ids               = [azurerm_application_security_group.graphdb_vmss.id]
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

  # Wait for dependent resources (until we add retry mechanism in the user data script)
  depends_on = [
    # DNS
    azurerm_private_dns_zone.graphdb,
    azurerm_private_dns_zone_virtual_network_link.graphdb,
    # NAT
    azurerm_nat_gateway.graphdb,
    azurerm_nat_gateway_public_ip_association.graphdb_nat_gateway,
    azurerm_subnet_nat_gateway_association.graphdb_nat_gateway,
    # Disks
    azurerm_managed_disk.managed_disks,
    # NSG
    azurerm_network_security_group.graphdb_vmss,
    azurerm_subnet_network_security_group_association.graphdb_vmss,
    # TODO: wait for internal and outbound rules?
    # Configurations
    azurerm_app_configuration_key.graphdb_cluster_token,
    azurerm_app_configuration_key.graphdb_java_options,
    azurerm_app_configuration_key.graphdb_license,
    azurerm_app_configuration_key.graphdb_password,
    azurerm_app_configuration_key.graphdb_properties
  ]
}

#
# Autoscaling
#

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

  notification {
    email {
      custom_emails = var.scaleset_actions_recipients_email_list
    }
  }
}
