data "azurerm_resource_group" "graphdb" {
  name = var.resource_group_name
}

data "azurerm_subnet" "graphdb" {
  name                 = var.graphdb_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.network_interface_name
}

data "azurerm_user_assigned_identity" "graphdb-instances" {
  name                = var.identity_name
  resource_group_name = var.resource_group_name
}

locals {
  resource_group = data.azurerm_resource_group.graphdb.name
  location       = data.azurerm_resource_group.graphdb.location

  subnet_id   = data.azurerm_subnet.graphdb.id
  subnet_cidr = data.azurerm_subnet.graphdb.address_prefix
}

# TODO: Move out of here to a sg module ?
# Create Network Security Group and rules
resource "azurerm_network_security_group" "graphdb" {
  name                = "${var.resource_name_prefix}-nic"
  resource_group_name = local.resource_group
  location            = local.location

  tags = var.tags
}

# TODO: This won't matter when we remove the public IPs of the machines. We'd have to use Bastion
resource "azurerm_network_security_rule" "graphdb-inbound-ssh" {
  count = var.source_ssh_blocks != null ? 1 : 0

  resource_group_name         = local.resource_group
  network_security_group_name = azurerm_network_security_group.graphdb.name

  name                       = "graphdb_ssh_inbound"
  description                = "Allow specified CIDRs SSH access to the GraphDB instances."
  priority                   = 900
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = 22
  source_address_prefixes    = var.source_ssh_blocks
  destination_address_prefix = local.subnet_cidr
}

# TODO: probably not the place for this to be here.. could create the NSG outside and pass it here and to the lb module?
# TODO: We need better segmentation of NSGs, traffic should be limited to the LB only
resource "azurerm_network_security_rule" "graphdb-proxies-inbound" {
  resource_group_name         = local.resource_group
  network_security_group_name = azurerm_network_security_group.graphdb.name

  name                       = "graphdb_proxies_inbound"
  description                = "Allow internet traffic to reach the GraphDB proxies"
  priority                   = 1000
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "7201"
  source_address_prefixes    = ["0.0.0.0/0"]
  destination_address_prefix = local.subnet_cidr
}

locals {
  user_data_script = var.custom_user_data != null ? var.custom_user_data : templatefile("${path.module}/templates/entrypoint.sh.tpl", {
    load_balancer_fqdn : var.load_balancer_fqdn
    key_vault_name : var.key_vault_name
    data_disk_performance_tier : var.data_disk_performance_tier
    disk_size_gb : var.disk_size_gb
  })
}

# Create virtual machine
resource "azurerm_linux_virtual_machine_scale_set" "graphdb" {
  name                = var.resource_name_prefix
  resource_group_name = local.resource_group
  location            = local.location

  source_image_id = var.image_id
  user_data       = base64encode(local.user_data_script)

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.graphdb-instances.id]
  }

  sku          = var.instance_type
  instances    = var.node_count
  zones        = var.zones
  zone_balance = true
  upgrade_mode = "Manual"

  computer_name_prefix = "${var.resource_name_prefix}-"
  admin_username       = "graphdb"

  network_interface {
    name                      = "${var.resource_name_prefix}-vmss-nic"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.graphdb.id

    ip_configuration {
      name      = "${var.resource_name_prefix}-ip-config"
      primary   = true
      subnet_id = local.subnet_id

      load_balancer_backend_address_pool_ids = [var.load_balancer_backend_address_pool_id]

      # TODO: Temporary for testing. Remove after configuring the LB
      public_ip_address {
        name = "first"
      }
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

resource "azurerm_role_definition" "managed_disk_manager" {
  name        = "ManagedDiskManager"
  scope       = data.azurerm_resource_group.graphdb.id
  description = "This is a custom role created via Terraform required for creating data disks for GraphDB"

  permissions {
    actions = [
      "Microsoft.Compute/disks/read",
      "Microsoft.Compute/disks/write",
      "Microsoft.Compute/virtualMachineScaleSets/read",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/write",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.Network/loadBalancers/backendAddressPools/join/action",
      "Microsoft.Network/networkSecurityGroups/join/action"
    ]
    not_actions = []
  }

  assignable_scopes = [
    data.azurerm_resource_group.graphdb.id
  ]
  depends_on = [data.azurerm_resource_group.graphdb]
}

resource "azurerm_role_assignment" "rg-contributor-role" {
  principal_id         = data.azurerm_user_assigned_identity.graphdb-instances.principal_id
  scope                = data.azurerm_resource_group.graphdb.id
  role_definition_name = "ManagedDiskManager"
  depends_on = [azurerm_role_definition.managed_disk_manager]
}
