locals {
  user_data_script = templatefile("${path.module}/templates/entrypoint.sh.tpl", {
    graphdb_external_address_fqdn : var.graphdb_external_address_fqdn
    key_vault_name : var.key_vault_name
    disk_iops_read_write : var.disk_iops_read_write
    disk_mbps_read_write : var.disk_mbps_read_write
    disk_size_gb : var.disk_size_gb
    backup_storage_container_url : var.backup_storage_container_url
    backup_schedule : var.backup_schedule
  })
}
