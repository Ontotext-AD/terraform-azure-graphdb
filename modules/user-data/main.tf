locals {
  user_data_script = templatefile("${path.module}/templates/entrypoint.sh.tpl", {
    graphdb_external_address_fqdn : var.graphdb_external_address_fqdn
    app_config_name : var.app_configuration_name
    disk_storage_account_type : var.disk_storage_account_type
    disk_iops_read_write : var.disk_iops_read_write
    disk_mbps_read_write : var.disk_mbps_read_write
    disk_size_gb : var.disk_size_gb
    disk_network_access_policy : var.disk_network_access_policy
    disk_public_network_access : var.disk_public_network_access
    backup_storage_account_name : var.backup_storage_account_name
    backup_storage_container_name : var.backup_storage_container_name
    backup_schedule : var.backup_schedule
  })
}
