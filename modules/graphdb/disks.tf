#
# Managed disks
#

locals {
  lun_map = [
    for i, zone in var.zones : {
      datadisk_name = "disk-${var.resource_name_prefix}-${zone}-1"
      zone          = zone
    }
  ]
}

# Creates managed disks which will be attached to the VMSS instances by the userdata script
resource "azurerm_managed_disk" "managed_disks" {
  for_each = {
    for entry in local.lun_map : entry.datadisk_name => entry.zone
  }

  name                = each.key
  resource_group_name = var.resource_group_name
  location            = var.location
  zone                = each.value

  storage_account_type          = var.disk_storage_account_type
  create_option                 = "Empty"
  disk_size_gb                  = var.disk_size_gb
  disk_iops_read_write          = var.disk_iops_read_write
  disk_mbps_read_write          = var.disk_mbps_read_write
  public_network_access_enabled = var.disk_public_network_access
  network_access_policy         = var.disk_network_access_policy
}
