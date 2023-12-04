# Create virtual machine scale set
resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = var.resource_group_name
  location            = var.location

  source_image_id = var.image_id
  user_data       = base64encode(var.user_data_script)

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
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

  tags = var.tags
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

  tags = var.tags
}
